import Foundation

struct AppShortcut: Identifiable, Codable, Equatable {
    let id: UUID
    var displayName: String
    var bundleIdentifier: String
    var appURL: URL
    var iconFileName: String
    var customLabel: String?
    var backgroundColorHex: String? = nil

    init(displayName: String, bundleIdentifier: String, appURL: URL, iconFileName: String, customLabel: String? = nil, backgroundColorHex: String? = nil) {
        self.id = UUID()
        self.displayName = displayName
        self.bundleIdentifier = bundleIdentifier
        self.appURL = appURL
        self.iconFileName = iconFileName
        self.customLabel = customLabel
        self.backgroundColorHex = backgroundColorHex
    }

    /// The label to display — uses customLabel if set, otherwise falls back to displayName.
    var label: String {
        customLabel ?? displayName
    }
}
