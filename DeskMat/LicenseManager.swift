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
    private static let variantID    = "1511534"
    private static let keychainService = "com.kinghorn.deskmat"
    private static let keychainAccount = "license"
    private static let baseURL      = "https://api.lemonsqueezy.com/v1/licenses"

    private let log = Logger(subsystem: "com.kinghorn.deskmat", category: "LicenseManager")

    var isPro = false

    #if DEBUG
    @ObservationIgnored
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
        let instanceName = (Host.current().localizedName ?? "Mac")
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "Mac"
        let body = "license_key=\(licenseKey)&instance_name=\(instanceName)"

        do {
            let (json, status) = try await post(endpoint: "activate", body: body)

            if status == 200,
               let activated = json["activated"] as? Bool, activated,
               let instance  = json["instance"]  as? [String: Any],
               let instanceId = instance["id"] as? String {
                saveToKeychain(licenseKey: licenseKey, instanceId: instanceId)
                await MainActor.run { isPro = true }
                return .success
            }

            let error = json["error"] as? String ?? ""
            if status == 400 && error.lowercased().contains("already") { return .alreadyActive }
            if status == 404 { return .invalid }
            return error.isEmpty ? .invalid : .error(error)

        } catch {
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

        do {
            let (json, status) = try await post(endpoint: "validate", body: body)

            if status == 200, let valid = json["valid"] as? Bool, valid {
                return // already true
            } else if status != 0 {
                // Definitive server response — key revoked or invalid
                clearKeychain()
                await MainActor.run { isPro = false }
            }
            // status == 0 means URLSession threw before we got a response (offline) — keep true
        } catch {
            log.warning("License validation failed (offline?): \(error.localizedDescription)")
        }
    }

    /// Deactivate this machine so the key can be used on another Mac.
    func deactivate() async -> DeactivationResult {
        guard let (licenseKey, instanceId) = readFromKeychain() else {
            return .error("No active license found.")
        }

        let body = "license_key=\(licenseKey)&instance_id=\(instanceId)"

        do {
            let (json, status) = try await post(endpoint: "deactivate", body: body)

            if status == 200, let deactivated = json["deactivated"] as? Bool, deactivated {
                clearKeychain()
                await MainActor.run { isPro = false }
                return .success
            }

            let error = json["error"] as? String ?? "Deactivation failed."
            return .error(error)
        } catch {
            return .error(error.localizedDescription)
        }
    }

    /// Last 4 characters of the stored key, for display. e.g. "••••-••••-••••-AB12"
    var licenseKeyHint: String? {
        guard let (key, _) = readFromKeychain() else { return nil }
        return "••••-••••-••••-\(key.suffix(4))"
    }

    // MARK: - Networking

    private func post(endpoint: String, body: String) async throws -> ([String: Any], Int) {
        var request = URLRequest(url: URL(string: "\(Self.baseURL)/\(endpoint)")!)
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
    }

    private func saveToKeychain(licenseKey: String, instanceId: String) {
        guard let data = try? JSONEncoder().encode(StoredLicense(licenseKey: licenseKey, instanceId: instanceId)) else { return }
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: Self.keychainService,
            kSecAttrAccount: Self.keychainAccount
        ]
        SecItemDelete(query as CFDictionary)
        var addQuery = query
        addQuery[kSecValueData] = data
        SecItemAdd(addQuery as CFDictionary, nil)
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
