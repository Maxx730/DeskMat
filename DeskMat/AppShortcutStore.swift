import AppKit
import Foundation
import OSLog

private let logger = Logger(subsystem: "com.kinghorn.deskmat", category: "AppShortcutStore")

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

    // MARK: - Load / Save

    static func load() -> [DockItem] {
        if !FileManager.default.fileExists(atPath: shortcutsFileURL.path(percentEncoded: false)) {
            initializeWithDefaults()
        }
        guard FileManager.default.fileExists(atPath: shortcutsFileURL.path(percentEncoded: false)) else {
            return []
        }
        do {
            let data = try Data(contentsOf: shortcutsFileURL)
            // Try current [DockItem] format first
            if let items = try? JSONDecoder().decode([DockItem].self, from: data) {
                return items
            }
            // Fall back to legacy [AppShortcut] format, upgrade and resave
            let legacy = try JSONDecoder().decode([AppShortcut].self, from: data)
            let items = legacy.map { DockItem.shortcut($0) }
            save(items)
            return items
        } catch {
            logger.error("Failed to load shortcuts: \(error.localizedDescription)")
            let backupURL = shortcutsFileURL.deletingPathExtension().appendingPathExtension("bak.json")
            try? FileManager.default.copyItem(at: shortcutsFileURL, to: backupURL)
            return []
        }
    }

    static func save(_ items: [DockItem]) {
        do {
            try ensureDirectories()
            let data = try JSONEncoder().encode(items)
            try data.write(to: shortcutsFileURL, options: .atomic)
        } catch {
            logger.error("Failed to save shortcuts: \(error.localizedDescription)")
        }
    }

    // MARK: - Icon Management

    static func copyIcon(from sourceURL: URL, for shortcutID: UUID) throws -> String {
        try ensureDirectories()
        let ext = sourceURL.pathExtension.isEmpty ? "png" : sourceURL.pathExtension
        let fileName = "\(shortcutID.uuidString).\(ext)"
        let destination = iconsDirectory.appending(path: fileName)
        let data = try Data(contentsOf: sourceURL)
        try data.write(to: destination, options: .atomic)
        return fileName
    }

    static func copyIcon(from image: NSImage, for shortcutID: UUID) throws -> String {
        try ensureDirectories()
        guard
            let tiffData = image.tiffRepresentation,
            let bitmap   = NSBitmapImageRep(data: tiffData),
            let pngData  = bitmap.representation(using: .png, properties: [:])
        else { throw CocoaError(.fileWriteUnknown) }
        let fileName = "\(shortcutID.uuidString).png"
        try pngData.write(to: iconsDirectory.appending(path: fileName), options: .atomic)
        return fileName
    }

    static func deleteIcon(named fileName: String) {
        let url = iconsDirectory.appending(path: fileName)
        try? FileManager.default.removeItem(at: url)
    }

    /// Deletes all icon files associated with a dock item, including folder children and custom folder icons.
    static func deleteIcons(for item: DockItem) {
        switch item {
        case .shortcut(let s):
            deleteIcon(named: s.iconFileName)
        case .folder(let f):
            if let icon = f.iconFileName { deleteIcon(named: icon) }
            for shortcut in f.shortcuts { deleteIcon(named: shortcut.iconFileName) }
        }
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

        save(shortcuts.map { .shortcut($0) })
    }

    // MARK: - Export / Import (.dskm)

    private struct DskmArchive: Codable {
        let items: [DockItem]
        let icons: [String: String]
    }

    private struct LegacyDskmArchive: Codable {
        let shortcuts: [AppShortcut]
        let icons: [String: String]
    }

    static func exportDock(to destinationURL: URL) throws {
        let fm = FileManager.default

        let items: [DockItem]
        if fm.fileExists(atPath: shortcutsFileURL.path(percentEncoded: false)) {
            let data = try Data(contentsOf: shortcutsFileURL)
            if let decoded = try? JSONDecoder().decode([DockItem].self, from: data) {
                items = decoded
            } else {
                let legacy = try JSONDecoder().decode([AppShortcut].self, from: data)
                items = legacy.map { .shortcut($0) }
            }
        } else {
            items = []
        }

        var icons: [String: String] = [:]
        if fm.fileExists(atPath: iconsDirectory.path(percentEncoded: false)) {
            let iconFiles = try fm.contentsOfDirectory(at: iconsDirectory, includingPropertiesForKeys: nil)
            for file in iconFiles {
                let imageData = try Data(contentsOf: file)
                icons[file.lastPathComponent] = imageData.base64EncodedString()
            }
        }

        let archive = DskmArchive(items: items, icons: icons)
        let encoded = try JSONEncoder().encode(archive)
        try encoded.write(to: destinationURL, options: .atomic)
    }

    static func importDock(from sourceURL: URL) throws -> [DockItem] {
        let data = try Data(contentsOf: sourceURL)

        let items: [DockItem]
        let iconMap: [String: String]

        if let archive = try? JSONDecoder().decode(DskmArchive.self, from: data) {
            items = archive.items
            iconMap = archive.icons
        } else {
            let legacy = try JSONDecoder().decode(LegacyDskmArchive.self, from: data)
            items = legacy.shortcuts.map { .shortcut($0) }
            iconMap = legacy.icons
        }

        try ensureDirectories()

        let itemsData = try JSONEncoder().encode(items)
        try itemsData.write(to: shortcutsFileURL, options: .atomic)

        let maxIcons    = 50
        let maxIconSize = 512 * 1024
        var iconsWritten = 0
        for (fileName, base64) in iconMap {
            guard iconsWritten < maxIcons else {
                logger.warning("Import icon limit (\(maxIcons)) reached — remaining icons skipped")
                break
            }
            let sanitized = URL(fileURLWithPath: fileName).lastPathComponent
            guard !sanitized.isEmpty, !sanitized.hasPrefix(".") else { continue }
            guard let imageData = Data(base64Encoded: base64) else { continue }
            guard imageData.count <= maxIconSize else {
                logger.warning("Import skipped '\(sanitized)' — exceeds \(maxIconSize / 1024) KB size limit")
                continue
            }
            let dest = iconsDirectory.appending(path: sanitized)
            try imageData.write(to: dest, options: .atomic)
            iconsWritten += 1
        }

        return items
    }

}
