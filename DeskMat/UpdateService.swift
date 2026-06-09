import Foundation
import OSLog

private let logger = Logger(subsystem: "com.kinghorn.deskmat", category: "UpdateService")

private let productID      = "784415ba-f43c-4a21-91c7-ec9ad1968406"
private let minimumInterval: TimeInterval = 60 * 60   // 1 hour between auto-checks

// MARK: - Response Model

private struct VersionCheckResponse: Codable {
    let upToDate:      Bool
    let latestVersion: String
    let downloadURL:   URL?
    let releaseNotes:  String?

    enum CodingKeys: String, CodingKey {
        case upToDate      = "up_to_date"
        case latestVersion = "latest_version"
        case downloadURL   = "download_url"
        case releaseNotes  = "release_notes"
    }
}

// MARK: - Update Service

@Observable
final class UpdateService {
    private(set) var isChecking:        Bool    = false
    private(set) var isUpdateAvailable: Bool    = false
    private(set) var latestVersion:     String  = ""
    private(set) var downloadURL:       URL?    = nil
    private(set) var releaseNotes:      String? = nil

    private static let lastCheckKey = "lastUpdateCheckDate"

    #if DEBUG
    func forceUpdateAvailable(version: String = "99.0.0") {
        latestVersion     = version
        isUpdateAvailable = true
        downloadURL       = URL(string: "https://auth.cepholotech.com")
        releaseNotes      = "Debug: simulated update available."
    }
    #endif

    /// Checks for an update. Pass `force: true` to skip the 1-hour throttle (e.g. manual trigger).
    func check(force: Bool = false) async {
        guard !isChecking else { return }

        if !force, let last = UserDefaults.standard.object(forKey: Self.lastCheckKey) as? Date,
           Date().timeIntervalSince(last) < minimumInterval {
            return
        }

        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"

        var components = URLComponents(string: "https://auth.cepholotech.com/versions/check")!
        components.queryItems = [
            URLQueryItem(name: "product_id",      value: productID),
            URLQueryItem(name: "platform",        value: "mac"),
            URLQueryItem(name: "current_version", value: currentVersion),
        ]

        guard let url = components.url else { return }

        await MainActor.run { isChecking = true }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            UserDefaults.standard.set(Date(), forKey: Self.lastCheckKey)

            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                logger.warning("Version check returned non-200: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                await MainActor.run { isChecking = false }
                return
            }

            let decoded = try JSONDecoder().decode(VersionCheckResponse.self, from: data)

            await MainActor.run {
                latestVersion     = decoded.latestVersion
                isUpdateAvailable = !decoded.upToDate
                downloadURL       = decoded.downloadURL
                releaseNotes      = decoded.releaseNotes
                isChecking        = false
            }
        } catch {
            logger.error("Version check failed: \(error.localizedDescription)")
            await MainActor.run { isChecking = false }
        }
    }
}
