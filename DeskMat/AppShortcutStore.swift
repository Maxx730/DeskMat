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

    /// Exports the current dock configuration and icons to a .dskm archive at the given URL.
    static func exportDock(to destinationURL: URL) throws {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appending(path: UUID().uuidString)
        let tempIcons = tempDir.appending(path: "Icons")

        defer { try? fm.removeItem(at: tempDir) }

        try fm.createDirectory(at: tempIcons, withIntermediateDirectories: true)

        // Copy shortcuts.json
        if fm.fileExists(atPath: shortcutsFileURL.path(percentEncoded: false)) {
            try fm.copyItem(at: shortcutsFileURL, to: tempDir.appending(path: "shortcuts.json"))
        } else {
            // Write an empty array if no shortcuts exist
            try Data("[]".utf8).write(to: tempDir.appending(path: "shortcuts.json"))
        }

        // Copy all icon files
        if fm.fileExists(atPath: iconsDirectory.path(percentEncoded: false)) {
            let iconFiles = try fm.contentsOfDirectory(at: iconsDirectory, includingPropertiesForKeys: nil)
            for file in iconFiles {
                try fm.copyItem(at: file, to: tempIcons.appending(path: file.lastPathComponent))
            }
        }

        // Remove destination if it already exists
        if fm.fileExists(atPath: destinationURL.path(percentEncoded: false)) {
            try fm.removeItem(at: destinationURL)
        }

        // Use ditto to create a zip archive
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--sequesterRsrc",
                             tempDir.path(percentEncoded: false),
                             destinationURL.path(percentEncoded: false)]
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw NSError(domain: "DeskMat", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: Strings.Errors.failedToCreateArchive])
        }
    }

    /// Imports a dock configuration from a .dskm archive, replacing the current shortcuts and icons.
    static func importDock(from sourceURL: URL) throws -> [AppShortcut] {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appending(path: UUID().uuidString)

        defer { try? fm.removeItem(at: tempDir) }

        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // Extract the archive using ditto
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k",
                             sourceURL.path(percentEncoded: false),
                             tempDir.path(percentEncoded: false)]
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw NSError(domain: "DeskMat", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: Strings.Errors.failedToExtractArchive])
        }

        // Read the shortcuts from the extracted archive
        let extractedJSON = tempDir.appending(path: "shortcuts.json")
        guard fm.fileExists(atPath: extractedJSON.path(percentEncoded: false)) else {
            throw NSError(domain: "DeskMat", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: Strings.Errors.invalidDskmFile])
        }

        let data = try Data(contentsOf: extractedJSON)
        let shortcuts = try JSONDecoder().decode([AppShortcut].self, from: data)

        // Ensure our store directories exist
        try ensureDirectories()

        // Replace shortcuts.json
        try data.write(to: shortcutsFileURL, options: .atomic)

        // Replace icons — copy extracted icons into our Icons directory
        let extractedIcons = tempDir.appending(path: "Icons")
        if fm.fileExists(atPath: extractedIcons.path(percentEncoded: false)) {
            let iconFiles = try fm.contentsOfDirectory(at: extractedIcons, includingPropertiesForKeys: nil)
            for file in iconFiles {
                let dest = iconsDirectory.appending(path: file.lastPathComponent)
                if fm.fileExists(atPath: dest.path(percentEncoded: false)) {
                    try fm.removeItem(at: dest)
                }
                try fm.copyItem(at: file, to: dest)
            }
        }

        return shortcuts
    }

}
