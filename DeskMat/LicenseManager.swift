import Foundation
import Security
import OSLog

enum ActivationResult {
    case success
    case invalid
    case alreadyActive
    case error(String)
}

enum DeactivationResult {
    case success
    case error(String)
}

@Observable
final class LicenseManager {
    internal static let keychainService    = "com.kinghorn.deskmat"
    internal static let keychainAccount    = "license_v2"
    private  static let hardwareIdAccount  = "hardware_id_v1"
    #if DEBUG
    internal static let baseURL: String = ProcessInfo.processInfo.environment["DESKMAT_API_URL"] ?? "https://auth.cepholotech.com"
    #else
    private static let baseURL = "https://auth.cepholotech.com"
    #endif

    private let log = Logger(subsystem: "com.kinghorn.deskmat", category: "LicenseManager")

    var isPro = false
    var lastValidated: Date? = nil

    #if DEBUG
    private var _lastDebugProOverride = UserDefaults.standard.bool(forKey: "debugProOverride")
    #endif

    init() {
        Task { await refreshFromKeychain() }

        #if DEBUG
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            let current = UserDefaults.standard.bool(forKey: "debugProOverride")
            guard current != _lastDebugProOverride else { return }
            _lastDebugProOverride = current
            Task { @MainActor [weak self] in self?.isPro = current }
        }
        #endif
    }

    // MARK: - Public API

    func activate(licenseKey: String) async -> ActivationResult {
        let trimmed = licenseKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: "_", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == "ceph", parts[2].count >= 8 else {
            log.warning("Activation rejected — invalid key format")
            return .invalid
        }

        let hardwareId = generateOrRetrieveHardwareId()
        log.info("Activating license key ending in …\(trimmed.suffix(4))")

        do {
            let (json, status) = try await post(endpoint: "verify", body: ["key": trimmed, "hardware_id": hardwareId])

            if status == 200, let valid = json["valid"] as? Bool {
                if valid {
                    guard saveToKeychain(key: trimmed, hardwareId: hardwareId) else {
                        return .error("License activated but could not be saved. Please try again.")
                    }
                    await MainActor.run { isPro = true; lastValidated = Date() }
                    log.info("Activation succeeded")
                    return .success
                } else {
                    log.warning("Activation rejected — key invalid or seat limit reached")
                    return .invalid
                }
            }

            let error = json["error"] as? String ?? ""
            log.warning("Activation failed — status: \(status), error: \(error)")
            return error.isEmpty ? .invalid : .error(error)

        } catch {
            if let urlError = error as? URLError, urlError.code == .notConnectedToInternet || urlError.code == .networkConnectionLost {
                return .error("No internet connection. Please check your network and try again.")
            }
            log.error("Activation request failed: \(error.localizedDescription)")
            return .error(error.localizedDescription)
        }
    }

    func refreshFromKeychain() async {
        guard let (key, hardwareId) = readFromKeychain() else {
            await MainActor.run { isPro = false }
            return
        }

        // Optimistically grant pro while network call is in flight
        await MainActor.run { isPro = true }

        for attempt in 1...2 {
            do {
                let (json, status) = try await post(endpoint: "verify", body: ["key": key, "hardware_id": hardwareId])

                if status == 200, let valid = json["valid"] as? Bool {
                    if !valid {
                        // Server explicitly says the key is invalid/revoked — clear it
                        log.warning("License key revoked by server, clearing Keychain")
                        clearKeychain()
                        await MainActor.run { isPro = false }
                    } else {
                        await MainActor.run { lastValidated = Date() }
                    }
                }
                // Any non-200 (5xx, timeout surfaced as non-throw, etc.) → keep isPro = true
                // Only a definitive valid:false on a 200 response revokes the license
                return
            } catch {
                if attempt < 2 {
                    log.warning("License validation attempt \(attempt) failed, retrying: \(error.localizedDescription)")
                    try? await Task.sleep(for: .milliseconds(500))
                } else {
                    log.warning("License validation failed (offline?): \(error.localizedDescription)")
                }
            }
        }
    }

    func deactivate() async -> DeactivationResult {
        guard let (key, hardwareId) = readFromKeychain() else {
            return .error("No active license found.")
        }

        log.info("Deactivating license key ending in …\(key.suffix(4))")

        do {
            let (json, status) = try await post(endpoint: "deactivate", body: ["key": key, "hardware_id": hardwareId])

            if status == 200, let success = json["success"] as? Bool, success {
                clearKeychain()
                await MainActor.run { isPro = false }
                log.info("Deactivation succeeded")
                return .success
            }

            let error = json["error"] as? String ?? "Deactivation failed."
            log.warning("Deactivation failed — status: \(status), error: \(error)")
            return .error(error)
        } catch {
            if let urlError = error as? URLError, urlError.code == .notConnectedToInternet || urlError.code == .networkConnectionLost {
                return .error("No internet connection. Please check your network and try again.")
            }
            log.error("Deactivation request failed: \(error.localizedDescription)")
            return .error(error.localizedDescription)
        }
    }

    /// Clears the Keychain entry and resets isPro. Used by the debug reset flow only.
    #if DEBUG
    func resetForDebug() {
        clearKeychain()
        isPro = false
    }
    #endif

    var licenseKeyHint: String? {
        guard let (key, _) = readFromKeychain() else { return nil }
        let parts = key.split(separator: "_", omittingEmptySubsequences: false)
        let slug = parts.count == 3 ? String(parts[1]) : "•••"
        return "ceph_\(slug)_…\(key.suffix(4))"
    }

    // MARK: - Hardware ID

    private func generateOrRetrieveHardwareId() -> String {
        // Dedicated entry — stable across all activation attempts, even failed ones
        if let id = readHardwareIdFromKeychain() { return id }
        // Legacy fallback — hardware ID bundled with a previously saved license key
        if let (_, existingId) = readFromKeychain() { return existingId }
        // First run — generate, persist, and return
        let newId = UUID().uuidString
        saveHardwareIdToKeychain(newId)
        return newId
    }

    private func readHardwareIdFromKeychain() -> String? {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: Self.keychainService,
            kSecAttrAccount: Self.hardwareIdAccount,
            kSecReturnData:  true,
            kSecMatchLimit:  kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    private func saveHardwareIdToKeychain(_ id: String) -> Bool {
        guard let data = id.data(using: .utf8) else { return false }
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: Self.keychainService,
            kSecAttrAccount: Self.hardwareIdAccount
        ]
        SecItemDelete(query as CFDictionary)
        var addQuery = query
        addQuery[kSecValueData] = data
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status != errSecSuccess {
            log.error("Hardware ID Keychain save failed with status: \(status)")
            return false
        }
        return true
    }

    // MARK: - Networking

    private func post(endpoint: String, body: [String: String]) async throws -> ([String: Any], Int) {
        guard let url = URL(string: "\(Self.baseURL)/\(endpoint)") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json   = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        return (json, status)
    }

    // MARK: - Keychain

    private struct StoredLicense: Codable {
        let key: String
        let hardwareId: String
        let version: Int

        init(key: String, hardwareId: String, version: Int = 2) {
            self.key = key
            self.hardwareId = hardwareId
            self.version = version
        }
    }

    @discardableResult
    private func saveToKeychain(key: String, hardwareId: String) -> Bool {
        guard let data = try? JSONEncoder().encode(StoredLicense(key: key, hardwareId: hardwareId)) else {
            log.error("Failed to encode license for Keychain storage")
            return false
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
        if status != errSecSuccess {
            log.error("Keychain save failed with status: \(status)")
            return false
        }
        return true
    }

    private func readFromKeychain() -> (key: String, hardwareId: String)? {
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
              let stored = try? JSONDecoder().decode(StoredLicense.self, from: data) else { return nil }
        return (stored.key, stored.hardwareId)
    }

    private func clearKeychain() {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: Self.keychainService,
            kSecAttrAccount: Self.keychainAccount
        ]
        SecItemDelete(query as CFDictionary)
    }
}
