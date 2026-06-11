import Foundation
import Security
import Network
import CryptoKit
import AppKit
import OSLog

// MARK: - Errors

enum EveAuthError: LocalizedError {
    case portInUse
    case timeout
    case stateMismatch
    case noCode
    case tokenExchangeFailed(String)
    case refreshFailed(String)
    case jwtDecodeFailed
    case notAuthenticated

    var errorDescription: String? {
        switch self {
        case .portInUse:                    return "Port 25734 is already in use. Close other apps and try again."
        case .timeout:                      return "Authentication timed out. Please try again."
        case .stateMismatch:                return "OAuth state mismatch — authentication may have been tampered with."
        case .noCode:                       return "No authorization code received from Eve SSO."
        case .tokenExchangeFailed(let m):   return "Token exchange failed: \(m)"
        case .refreshFailed(let m):         return "Token refresh failed: \(m)"
        case .jwtDecodeFailed:              return "Could not read character ID from Eve token."
        case .notAuthenticated:             return "Not authenticated with Eve Online."
        }
    }
}

// MARK: - Local HTTP Callback Server

private final class LocalCallbackServer {
    static let port: UInt16 = 25734
    private var listener: NWListener?

    func waitForCallback() async throws -> (String, String) {
        let listener: NWListener
        do {
            listener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: Self.port)!)
        } catch {
            throw EveAuthError.portInUse
        }
        self.listener = listener

        let serialQueue = DispatchQueue(label: "com.kinghorn.deskmat.eve.callback.lock")
        var didResume = false

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                func resumeOnce(_ result: Result<(String, String), Error>) {
                    serialQueue.sync {
                        guard !didResume else { return }
                        didResume = true
                        continuation.resume(with: result)
                    }
                }

                listener.newConnectionHandler = { connection in
                    connection.start(queue: .global(qos: .userInitiated))
                    connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, _, _ in
                        let result = Self.parseCallback(data: data)

                        let html = "<html><body style='font-family:system-ui;text-align:center;padding-top:80px'><h2>Authentication successful.</h2><p>You can close this tab and return to DeskMat.</p></body></html>"
                        let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(html.utf8.count)\r\nConnection: close\r\n\r\n\(html)"
                        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
                            connection.cancel()
                            listener.cancel()
                        })

                        resumeOnce(result)
                    }
                }

                listener.stateUpdateHandler = { state in
                    switch state {
                    case .failed(let error): resumeOnce(.failure(error))
                    case .cancelled:         resumeOnce(.failure(CancellationError()))
                    default:                 break
                    }
                }

                listener.start(queue: .global(qos: .userInitiated))
            }
        } onCancel: {
            listener.cancel()
        }
    }

    private static func parseCallback(data: Data?) -> Result<(String, String), Error> {
        guard let data, let request = String(data: data, encoding: .utf8) else {
            return .failure(EveAuthError.noCode)
        }
        // First line: "GET /callback?code=...&state=... HTTP/1.1"
        let firstLine = request.components(separatedBy: "\r\n").first ?? ""
        let urlPart   = firstLine.components(separatedBy: " ").dropFirst().first ?? ""

        guard urlPart.hasPrefix("/callback"),
              let queryStart = urlPart.firstIndex(of: "?") else {
            return .failure(EveAuthError.noCode)
        }

        let queryString = String(urlPart[urlPart.index(after: queryStart)...])
        var params: [String: String] = [:]
        for pair in queryString.components(separatedBy: "&") {
            let kv = pair.components(separatedBy: "=")
            if kv.count == 2 { params[kv[0]] = kv[1].removingPercentEncoding ?? kv[1] }
        }

        guard let code = params["code"], let state = params["state"] else {
            return .failure(EveAuthError.noCode)
        }
        return .success((code, state))
    }
}

// MARK: - Private Models

private struct EveTokens: Codable {
    let accessToken: String
    let refreshToken: String
    let tokenExpiry: Date
    let characterId: Int
    let characterName: String
}

private struct JWTPayload: Decodable { let sub: String }

private struct TokenResponse: Decodable {
    let access_token: String
    let refresh_token: String?
    let expires_in: Int
}

private struct CharacterInfo: Decodable { let name: String }

private extension Data {
    func base64URLEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - EveAuthService

@Observable
final class EveAuthService {
    private(set) var isAuthenticated = false
    private(set) var characterId     = 0
    private(set) var characterName   = ""
    private(set) var isConnecting    = false

    private(set) var accessToken  = ""
    private var refreshToken      = ""
    private var tokenExpiry: Date = .distantPast
    private var refreshInFlight: Task<String, Error>?
    private let refreshLock = NSLock()

    // Replace with the Client ID from developers.eveonline.com
    static let clientId    = "2a9c43e60c6144c69368c88cc811c161"
    static let redirectURI = "http://localhost:25734/callback"

    private static let scopes = [
        "esi-location.read_online.v1",
        "esi-location.read_location.v1",
        "esi-location.read_ship_type.v1",
        "esi-wallet.read_character_wallet.v1",
        "esi-skills.read_skillqueue.v1"
    ]

    private static let keychainService = "com.kinghorn.deskmat"
    private static let keychainAccount = "eve_auth_v1"
    private let log = Logger(subsystem: "com.kinghorn.deskmat", category: "EveAuthService")
    init() {
        if let tokens = loadFromKeychain() {
            accessToken    = tokens.accessToken
            refreshToken   = tokens.refreshToken
            tokenExpiry    = tokens.tokenExpiry
            characterId    = tokens.characterId
            characterName  = tokens.characterName
            isAuthenticated = true
            log.info("Loaded Eve auth — character: \(tokens.characterName)")
        }
    }

    // MARK: - Connect

    func connect() async throws {
        guard !isConnecting else { return }
        await MainActor.run { isConnecting = true }
        defer { Task { await MainActor.run { self.isConnecting = false } } }

        let (verifier, challenge) = generatePKCE()
        let state = UUID().uuidString

        var components = URLComponents(string: "https://login.eveonline.com/v2/oauth/authorize")!
        components.queryItems = [
            URLQueryItem(name: "response_type",         value: "code"),
            URLQueryItem(name: "client_id",             value: Self.clientId),
            URLQueryItem(name: "redirect_uri",          value: Self.redirectURI),
            URLQueryItem(name: "scope",                 value: Self.scopes.joined(separator: " ")),
            URLQueryItem(name: "code_challenge",        value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state",                 value: state)
        ]
        guard let authorizeURL = components.url else { return }

        let server = LocalCallbackServer()
        await MainActor.run { _ = NSWorkspace.shared.open(authorizeURL) }

        // Race callback against a 5-minute timeout
        let (code, returnedState) = try await withThrowingTaskGroup(of: (String, String).self) { group in
            group.addTask { try await server.waitForCallback() }
            group.addTask {
                try await Task.sleep(for: .seconds(300))
                throw EveAuthError.timeout
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }

        guard returnedState == state else { throw EveAuthError.stateMismatch }

        log.info("OAuth callback received, exchanging code...")
        let (newAccess, newRefresh, expiresIn) = try await exchangeCode(code, verifier: verifier)
        let expiry = Date().addingTimeInterval(Double(expiresIn))
        let charId = try extractCharacterId(from: newAccess)
        let charName = try await fetchCharacterName(id: charId)

        saveToKeychain(EveTokens(
            accessToken:  newAccess,
            refreshToken: newRefresh,
            tokenExpiry:  expiry,
            characterId:  charId,
            characterName: charName
        ))

        await MainActor.run {
            self.accessToken    = newAccess
            self.refreshToken   = newRefresh
            self.tokenExpiry    = expiry
            self.characterId    = charId
            self.characterName  = charName
            self.isAuthenticated = true
        }

        log.info("Eve auth complete — \(charName) (\(charId))")
    }

    // MARK: - Token Access (auto-refresh)

    func validAccessToken() async throws -> String {
        guard isAuthenticated else { throw EveAuthError.notAuthenticated }
        if Date() < tokenExpiry.addingTimeInterval(-60) { return accessToken }

        // Eve rotates refresh tokens on each use — only one refresh must fly at
        // a time or the second caller gets invalid_grant and disconnects the user.
        // NSLock makes the check-and-set of refreshInFlight atomic across threads.
        let task: Task<String, Error> = refreshLock.withLock {
            if let pending = refreshInFlight { return pending }
            let t = Task { [weak self] () throws -> String in
                defer {
                    self?.refreshLock.withLock { self?.refreshInFlight = nil }
                }
                guard let self else { throw EveAuthError.notAuthenticated }
                return try await self.performRefresh()
            }
            refreshInFlight = t
            return t
        }
        return try await task.value
    }

    private func performRefresh() async throws -> String {
        log.info("Access token expiring, refreshing...")

        var request = URLRequest(url: URL(string: "https://login.eveonline.com/v2/oauth/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data([
            "grant_type=refresh_token",
            "client_id=\(Self.clientId)",
            "refresh_token=\(refreshToken)"
        ].joined(separator: "&").utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            struct OAuthError: Decodable { let error: String }
            let isInvalidGrant = (try? JSONDecoder().decode(OAuthError.self, from: data))?.error == "invalid_grant"
            if status == 401 || isInvalidGrant {
                log.warning("Refresh token rejected (HTTP \(status)), clearing auth state")
                await MainActor.run { self.disconnect() }
            }
            throw EveAuthError.refreshFailed("HTTP \(status)")
        }

        let token = try JSONDecoder().decode(TokenResponse.self, from: data)
        let expiry = Date().addingTimeInterval(Double(token.expires_in))
        let newRefresh = token.refresh_token ?? refreshToken

        saveToKeychain(EveTokens(
            accessToken:   token.access_token,
            refreshToken:  newRefresh,
            tokenExpiry:   expiry,
            characterId:   characterId,
            characterName: characterName
        ))

        await MainActor.run {
            self.accessToken  = token.access_token
            self.refreshToken = newRefresh
            self.tokenExpiry  = expiry
        }

        return token.access_token
    }

    // MARK: - Disconnect

    func disconnect() {
        refreshLock.withLock {
            refreshInFlight?.cancel()
            refreshInFlight = nil
        }
        deleteFromKeychain()
        accessToken     = ""
        refreshToken    = ""
        tokenExpiry     = .distantPast
        characterId     = 0
        characterName   = ""
        isAuthenticated = false
        log.info("Eve account disconnected")
    }

    // MARK: - PKCE

    private func generatePKCE() -> (verifier: String, challenge: String) {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let verifier = Data(bytes).base64URLEncoded()
        let challengeData = Data(SHA256.hash(data: Data(verifier.utf8)))
        let challenge = challengeData.base64URLEncoded()
        return (verifier, challenge)
    }

    private func extractCharacterId(from jwt: String) throws -> Int {
        let parts = jwt.components(separatedBy: ".")
        guard parts.count == 3 else { throw EveAuthError.jwtDecodeFailed }

        var base64 = parts[1]
        let remainder = base64.count % 4
        if remainder != 0 { base64 += String(repeating: "=", count: 4 - remainder) }
        base64 = base64
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        guard let data = Data(base64Encoded: base64),
              let payload = try? JSONDecoder().decode(JWTPayload.self, from: data) else {
            throw EveAuthError.jwtDecodeFailed
        }

        // sub format: "CHARACTER:EVE:{characterId}"
        let subParts = payload.sub.components(separatedBy: ":")
        guard subParts.count == 3, let id = Int(subParts[2]) else {
            throw EveAuthError.jwtDecodeFailed
        }
        return id
    }

    // MARK: - Token Exchange

    private func exchangeCode(_ code: String, verifier: String) async throws -> (String, String, Int) {
        var request = URLRequest(url: URL(string: "https://login.eveonline.com/v2/oauth/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data([
            "grant_type=authorization_code",
            "client_id=\(Self.clientId)",
            "code=\(code)",
            "code_verifier=\(verifier)"
        ].joined(separator: "&").utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw EveAuthError.tokenExchangeFailed("HTTP \(status)") }

        let token = try JSONDecoder().decode(TokenResponse.self, from: data)
        guard let refresh = token.refresh_token else {
            throw EveAuthError.tokenExchangeFailed("No refresh token in response")
        }
        return (token.access_token, refresh, token.expires_in)
    }

    private func fetchCharacterName(id: Int) async throws -> String {
        let (data, _) = try await URLSession.shared.data(
            from: URL(string: "https://esi.evetech.net/latest/characters/\(id)/")!
        )
        return try JSONDecoder().decode(CharacterInfo.self, from: data).name
    }

    // MARK: - Keychain

    private func saveToKeychain(_ tokens: EveTokens) {
        guard let data = try? JSONEncoder().encode(tokens) else {
            log.error("Failed to encode Eve tokens")
            return
        }
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: Self.keychainService,
            kSecAttrAccount: Self.keychainAccount
        ]
        SecItemDelete(query as CFDictionary)
        var addQuery = query
        addQuery[kSecValueData] = data
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status != errSecSuccess { log.error("Keychain save failed: \(status)") }
    }

    private func loadFromKeychain() -> EveTokens? {
        let query: [CFString: Any] = [
            kSecClass:        kSecClassGenericPassword,
            kSecAttrService:  Self.keychainService,
            kSecAttrAccount:  Self.keychainAccount,
            kSecReturnData:   true,
            kSecMatchLimit:   kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data   = result as? Data,
              let tokens = try? JSONDecoder().decode(EveTokens.self, from: data) else { return nil }
        return tokens
    }

    private func deleteFromKeychain() {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: Self.keychainService,
            kSecAttrAccount: Self.keychainAccount
        ]
        SecItemDelete(query as CFDictionary)
    }
}
