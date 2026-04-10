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
    internal static let keychainService = "com.kinghorn.deskmat"
    internal static let keychainAccount = "license"
    #if DEBUG
    internal static let baseURL: String = ProcessInfo.processInfo.environment["DESKMAT_API_URL"] ?? "https://api.lemonsqueezy.com/v1/licenses"
    #else
    private static let baseURL = "https://api.lemonsqueezy.com/v1/licenses"
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

    /// Activate a license key on this machine. Stores the key + instance ID in Keychain on success.
    func activate(licenseKey: String) async -> ActivationResult {
        // Issue #6: Validate key format before hitting the network
        let trimmed = licenseKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count >= 8, trimmed.contains("-") else {
            log.warning("Activation rejected — invalid key format")
            return .invalid
        }

        // Issue #8: Log if hostname encoding falls back
        let rawHostname = Host.current().localizedName ?? "Mac"
        if rawHostname != "Mac", let encoded = rawHostname.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            log.debug("Activating with instance name: \(encoded)")
        } else {
            log.warning("Hostname encoding fell back to default 'Mac'")
        }
        let instanceName = rawHostname.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "Mac"
        let body = "license_key=\(trimmed)&instance_name=\(instanceName)"

        // Issue #10: Log activation attempt (last 4 chars only)
        log.info("Activating license key ending in …\(trimmed.suffix(4))")

        do {
            let (json, status) = try await post(endpoint: "activate", body: body)

            if status == 200,
               let activated = json["activated"] as? Bool, activated,
               let instance  = json["instance"]  as? [String: Any],
               let instanceId = instance["id"] as? String {
                guard saveToKeychain(licenseKey: trimmed, instanceId: instanceId) else {
                    return .error("License activated but could not be saved. Please try again.")
                }
                await MainActor.run { isPro = true; lastValidated = Date() }
                log.info("Activation succeeded")
                return .success
            }

            // Issue #7: Log unexpected response shape for debugging
            if status == 200 {
                log.warning("Activate returned 200 but unexpected shape: \(json.keys.joined(separator: ", "))")
            }

            let error = json["error"] as? String ?? ""
            if status == 400 && error.lowercased().contains("already") { return .alreadyActive }
            if status == 404 { return .invalid }
            log.warning("Activation failed — status: \(status), error: \(error)")
            return error.isEmpty ? .invalid : .error(error)

        } catch {
            // Issue #11: Distinguish offline from other errors
            if let urlError = error as? URLError, urlError.code == .notConnectedToInternet || urlError.code == .networkConnectionLost {
                return .error("No internet connection. Please check your network and try again.")
            }
            log.error("Activation request failed: \(error.localizedDescription)")
            return .error(error.localizedDescription)
        }
    }

    /// Validate the stored key against Lemon Squeezy. Soft-fails offline (keeps isPro = true).
    func refreshFromKeychain() async {
        guard let (licenseKey, instanceId) = readFromKeychain() else {
            await MainActor.run { isPro = false }
            return
        }

        // Optimistically grant pro while network call is in flight
        await MainActor.run { isPro = true }

        let body = "license_key=\(licenseKey)&instance_id=\(instanceId)"

        for attempt in 1...2 {
            do {
                let (json, status) = try await post(endpoint: "validate", body: body)

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

    /// Deactivate this machine so the key can be used on another Mac.
    func deactivate() async -> DeactivationResult {
        guard let (licenseKey, instanceId) = readFromKeychain() else {
            return .error("No active license found.")
        }

        // Issue #10: Log deactivation attempt
        log.info("Deactivating license key ending in …\(licenseKey.suffix(4))")

        let body = "license_key=\(licenseKey)&instance_id=\(instanceId)"

        do {
            let (json, status) = try await post(endpoint: "deactivate", body: body)

            if status == 200, let deactivated = json["deactivated"] as? Bool, deactivated {
                clearKeychain()
                await MainActor.run { isPro = false }
                log.info("Deactivation succeeded")
                return .success
            }

            // Issue #7: Log unexpected response shape
            if status == 200 {
                log.warning("Deactivate returned 200 but unexpected shape: \(json.keys.joined(separator: ", "))")
            }

            let error = json["error"] as? String ?? "Deactivation failed."
            log.warning("Deactivation failed — status: \(status), error: \(error)")
            return .error(error)
        } catch {
            // Issue #11: Distinguish offline from other errors
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

    /// Last 4 characters of the stored key, for display. e.g. "••••-••••-••••-AB12"
    var licenseKeyHint: String? {
        guard let (key, _) = readFromKeychain() else { return nil }
        return "••••-••••-••••-\(key.suffix(4))"
    }

    // MARK: - Networking

    private func post(endpoint: String, body: String) async throws -> ([String: Any], Int) {
        guard let url = URL(string: "\(Self.baseURL)/\(endpoint)") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json   = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        return (json, status)
    }

    // MARK: - Keychain

    private struct StoredLicense: Codable {
        let licenseKey: String
        let instanceId: String
        let version: Int

        init(licenseKey: String, instanceId: String, version: Int = 1) {
            self.licenseKey = licenseKey
            self.instanceId = instanceId
            self.version = version
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            licenseKey = try c.decode(String.self, forKey: .licenseKey)
            instanceId = try c.decode(String.self, forKey: .instanceId)
            // version defaults to 1 for data written before this field was added
            version = (try? c.decode(Int.self, forKey: .version)) ?? 1
        }
    }

    @discardableResult
    private func saveToKeychain(licenseKey: String, instanceId: String) -> Bool {
        guard let data = try? JSONEncoder().encode(StoredLicense(licenseKey: licenseKey, instanceId: instanceId)) else {
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

    private func readFromKeychain() -> (licenseKey: String, instanceId: String)? {
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
        return (stored.licenseKey, stored.instanceId)
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
