import Foundation

struct AppShortcut: Identifiable, Codable {
    let id: UUID
    var displayName: String
    var bundleIdentifier: String
    var appURL: URL
    var iconFileName: String
    var customLabel: String?

    init(displayName: String, bundleIdentifier: String, appURL: URL, iconFileName: String, customLabel: String? = nil) {
        self.id = UUID()
        self.displayName = displayName
        self.bundleIdentifier = bundleIdentifier
        self.appURL = appURL
        self.iconFileName = iconFileName
        self.customLabel = customLabel
    }

    /// The label to display — uses customLabel if set, otherwise falls back to displayName.
    var label: String {
        customLabel ?? displayName
    }
}
