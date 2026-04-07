import AppKit
import Foundation

enum AppShortcutStore {

    static var storeDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "DeskMat", directoryHint: .isDirectory)
    }

    static var iconsDirectory: URL {
        storeDirectory.appending(path: "Icons", directoryHint: .isDirectory)
    }

    static var shortcutsFileURL: URL {
        storeDirectory.appending(path: "shortcuts.json")
    }

    private static func ensureDirectories() throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: storeDirectory.path(percentEncoded: false)) {
            try fm.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
        }
        if !fm.fileExists(atPath: iconsDirectory.path(percentEncoded: false)) {
            try fm.createDirectory(at: iconsDirectory, withIntermediateDirectories: true)
        }
    }

    static func load() -> [AppShortcut] {
        // First launch: seed defaults before reading
        if !FileManager.default.fileExists(atPath: shortcutsFileURL.path(percentEncoded: false)) {
            initializeWithDefaults()
        }

        guard FileManager.default.fileExists(atPath: shortcutsFileURL.path(percentEncoded: false)) else {
            return []
        }
        do {
            let data = try Data(contentsOf: shortcutsFileURL)
            return try JSONDecoder().decode([AppShortcut].self, from: data)
        } catch {
            return []
        }
    }

    static func save(_ shortcuts: [AppShortcut]) {
        do {
            try ensureDirectories()
            let data = try JSONEncoder().encode(shortcuts)
            try data.write(to: shortcutsFileURL, options: .atomic)
        } catch {
            // Silently fail for MVP
        }
    }

    static func copyIcon(from sourceURL: URL, for shortcutID: UUID) throws -> String {
        try ensureDirectories()
        let ext = sourceURL.pathExtension.isEmpty ? "png" : sourceURL.pathExtension
        let fileName = "\(shortcutID.uuidString).\(ext)"
        let destination = iconsDirectory.appending(path: fileName)
        let data = try Data(contentsOf: sourceURL)
        try data.write(to: destination, options: .atomic)
        return fileName
    }

    static func deleteIcon(named fileName: String) {
        let url = iconsDirectory.appending(path: fileName)
        try? FileManager.default.removeItem(at: url)
    }

    static func iconURL(for fileName: String) -> URL {
        iconsDirectory.appending(path: fileName)
    }

    // MARK: - Default Seeding

    static func initializeWithDefaults() {
        guard (try? ensureDirectories()) != nil else { return }

        let defaults: [(name: String, bundleID: String)] = [
            ("Finder",          "com.apple.finder"),
            ("Safari",          "com.apple.Safari"),
            ("Mail",            "com.apple.mail"),
            ("Calendar",        "com.apple.iCal"),
            ("Messages",        "com.apple.MobileSMS"),
            ("Notes",           "com.apple.Notes"),
            ("Music",           "com.apple.Music"),
            ("Photos",          "com.apple.Photos"),
            ("Maps",            "com.apple.Maps"),
            ("System Settings", "com.apple.systempreferences"),
            ("Terminal",        "com.apple.Terminal"),
            ("App Store",       "com.apple.AppStore"),
        ]

        var shortcuts: [AppShortcut] = []

        for entry in defaults {
            guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: entry.bundleID) else {
                continue
            }

            let icon = NSWorkspace.shared.icon(forFile: appURL.path(percentEncoded: false))

            guard
                let tiffData = icon.tiffRepresentation,
                let bitmap = NSBitmapImageRep(data: tiffData),
                let pngData = bitmap.representation(using: .png, properties: [:])
            else { continue }

            let fileName = "\(UUID().uuidString).png"
            let dest = iconsDirectory.appending(path: fileName)

            guard (try? pngData.write(to: dest, options: .atomic)) != nil else { continue }

            let shortcut = AppShortcut(
                displayName: entry.name,
                bundleIdentifier: entry.bundleID,
                appURL: appURL,
                iconFileName: fileName
            )
            shortcuts.append(shortcut)
        }

        save(shortcuts)
    }

    // MARK: - Export / Import (.dskm)

    /// Flat archive format: shortcuts + base64-encoded icon data in a single JSON file.
    private struct DskmArchive: Codable {
        let shortcuts: [AppShortcut]
        let icons: [String: String] // iconFileName → base64-encoded image data
    }

    /// Exports the current dock to a single .dskm JSON file (no subprocess, sandbox-safe).
    static func exportDock(to destinationURL: URL) throws {
        let fm = FileManager.default

        let shortcuts: [AppShortcut]
        if fm.fileExists(atPath: shortcutsFileURL.path(percentEncoded: false)) {
            let data = try Data(contentsOf: shortcutsFileURL)
            shortcuts = try JSONDecoder().decode([AppShortcut].self, from: data)
        } else {
            shortcuts = []
        }

        var icons: [String: String] = [:]
        if fm.fileExists(atPath: iconsDirectory.path(percentEncoded: false)) {
            let iconFiles = try fm.contentsOfDirectory(at: iconsDirectory, includingPropertiesForKeys: nil)
            for file in iconFiles {
                let imageData = try Data(contentsOf: file)
                icons[file.lastPathComponent] = imageData.base64EncodedString()
            }
        }

        let archive = DskmArchive(shortcuts: shortcuts, icons: icons)
        let encoded = try JSONEncoder().encode(archive)
        try encoded.write(to: destinationURL, options: .atomic)
    }

    /// Imports a dock from a .dskm JSON file, replacing the current shortcuts and icons.
    static func importDock(from sourceURL: URL) throws -> [AppShortcut] {
        let data = try Data(contentsOf: sourceURL)
        let archive = try JSONDecoder().decode(DskmArchive.self, from: data)

        try ensureDirectories()

        let shortcutsData = try JSONEncoder().encode(archive.shortcuts)
        try shortcutsData.write(to: shortcutsFileURL, options: .atomic)

        for (fileName, base64) in archive.icons {
            guard let imageData = Data(base64Encoded: base64) else { continue }
            let dest = iconsDirectory.appending(path: fileName)
            try imageData.write(to: dest, options: .atomic)
        }

        return archive.shortcuts
    }

}
