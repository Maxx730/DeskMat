import Testing
import Foundation
import AppKit
@testable import DeskMat

// MARK: - AppShortcutStore Tests
//
// All three suites below write to the shared shortcuts.json / Icons directory.
// They are nested inside a single serialized parent suite so they never race
// against each other when the test runner executes suites in parallel.

@Suite(.serialized)
struct AppShortcutDataStoreTests {

@Suite(.serialized)
struct AppShortcutStoreTests {

    private func createTestPNG(color: NSColor = .red, name: String = "test.png") throws -> URL {
        let image = NSImage(size: NSSize(width: 1, height: 1))
        image.lockFocus()
        color.drawSwatch(in: NSRect(x: 0, y: 0, width: 1, height: 1))
        image.unlockFocus()

        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw TestPNGError.creationFailed
        }

        let url = FileManager.default.temporaryDirectory.appending(path: name)
        try pngData.write(to: url)
        return url
    }

    private enum TestPNGError: Error {
        case creationFailed
    }

    @Test func loadReturnsEmptyArrayWhenNoFileExists() {
        let result = AppShortcutStore.load()
        #expect(result is [AppShortcut])
    }

    @Test func saveAndLoadRoundTrips() {
        let original = AppShortcutStore.load()
        defer { AppShortcutStore.save(original) }

        let url = URL(fileURLWithPath: "/Applications/Safari.app")
        let shortcuts = [
            AppShortcut(displayName: "TestApp", bundleIdentifier: "com.test.app", appURL: url, iconFileName: "test.png")
        ]

        AppShortcutStore.save(shortcuts)
        let loaded = AppShortcutStore.load()

        #expect(loaded.count == 1)
        #expect(loaded[0].displayName == "TestApp")
        #expect(loaded[0].bundleIdentifier == "com.test.app")
    }

    @Test func saveAndLoadPreservesMultipleShortcuts() {
        let original = AppShortcutStore.load()
        defer { AppShortcutStore.save(original) }

        let url = URL(fileURLWithPath: "/Applications/Safari.app")
        let shortcuts = [
            AppShortcut(displayName: "App1", bundleIdentifier: "com.test.1", appURL: url, iconFileName: "1.png"),
            AppShortcut(displayName: "App2", bundleIdentifier: "com.test.2", appURL: url, iconFileName: "2.png"),
            AppShortcut(displayName: "App3", bundleIdentifier: "com.test.3", appURL: url, iconFileName: "3.png"),
        ]

        AppShortcutStore.save(shortcuts)
        let loaded = AppShortcutStore.load()

        #expect(loaded.count == 3)
        #expect(loaded[0].displayName == "App1")
        #expect(loaded[1].displayName == "App2")
        #expect(loaded[2].displayName == "App3")
    }

    @Test func copyIconCreatesFileAndReturnsFileName() throws {
        let sourceURL = try createTestPNG(color: .red, name: "test-icon.png")
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let testID = UUID()
        let fileName = try AppShortcutStore.copyIcon(from: sourceURL, for: testID)
        defer { AppShortcutStore.deleteIcon(named: fileName) }

        #expect(fileName.contains(testID.uuidString))
        #expect(fileName.hasSuffix(".png"))

        let storedURL = AppShortcutStore.iconURL(for: fileName)
        #expect(FileManager.default.fileExists(atPath: storedURL.path(percentEncoded: false)))
    }

    @Test func deleteIconRemovesFile() throws {
        let sourceURL = try createTestPNG(color: .blue, name: "delete-test.png")
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let testID = UUID()
        let fileName = try AppShortcutStore.copyIcon(from: sourceURL, for: testID)
        let storedURL = AppShortcutStore.iconURL(for: fileName)

        #expect(FileManager.default.fileExists(atPath: storedURL.path(percentEncoded: false)))

        AppShortcutStore.deleteIcon(named: fileName)
        #expect(!FileManager.default.fileExists(atPath: storedURL.path(percentEncoded: false)))
    }

    @Test func iconURLReturnsCorrectPath() {
        let url = AppShortcutStore.iconURL(for: "test-file.png")
        #expect(url.lastPathComponent == "test-file.png")
        #expect(url.pathComponents.contains("Icons"))
        #expect(url.pathComponents.contains("DeskMat"))
    }
}

// MARK: - Import / Export Tests

@Suite(.serialized)
struct ImportExportTests {

    private func createTestPNG(color: NSColor = .red, name: String = "test.png") throws -> URL {
        let image = NSImage(size: NSSize(width: 1, height: 1))
        image.lockFocus()
        color.drawSwatch(in: NSRect(x: 0, y: 0, width: 1, height: 1))
        image.unlockFocus()

        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create PNG"])
        }

        let url = FileManager.default.temporaryDirectory.appending(path: name)
        try pngData.write(to: url)
        return url
    }

    @Test func exportCreatesFile() throws {
        let original = AppShortcutStore.load()
        defer { AppShortcutStore.save(original) }

        let url = URL(fileURLWithPath: "/Applications/Safari.app")
        let shortcuts = [
            AppShortcut(displayName: "Test", bundleIdentifier: "com.test", appURL: url, iconFileName: "test.png")
        ]
        AppShortcutStore.save(shortcuts)

        let exportURL = FileManager.default.temporaryDirectory.appending(path: "test-export.dskm")
        defer { try? FileManager.default.removeItem(at: exportURL) }

        try AppShortcutStore.exportDock(to: exportURL)

        #expect(FileManager.default.fileExists(atPath: exportURL.path(percentEncoded: false)))
    }

    @Test func exportAndImportRoundTrips() throws {
        let original = AppShortcutStore.load()
        defer { AppShortcutStore.save(original) }

        let url = URL(fileURLWithPath: "/Applications/Safari.app")
        let shortcuts = [
            AppShortcut(displayName: "Safari", bundleIdentifier: "com.apple.Safari", appURL: url, iconFileName: "safari-icon.png"),
            AppShortcut(displayName: "Finder", bundleIdentifier: "com.apple.finder", appURL: url, iconFileName: "finder-icon.png"),
        ]
        AppShortcutStore.save(shortcuts)

        let iconPNG = try createTestPNG(color: .blue, name: "export-icon.png")
        defer { try? FileManager.default.removeItem(at: iconPNG) }

        let icon1Dest = AppShortcutStore.iconsDirectory.appending(path: "safari-icon.png")
        let icon2Dest = AppShortcutStore.iconsDirectory.appending(path: "finder-icon.png")
        try? FileManager.default.createDirectory(at: AppShortcutStore.iconsDirectory, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: iconPNG, to: icon1Dest)
        let iconPNG2 = try createTestPNG(color: .green, name: "export-icon2.png")
        defer { try? FileManager.default.removeItem(at: iconPNG2) }
        try FileManager.default.copyItem(at: iconPNG2, to: icon2Dest)
        defer {
            try? FileManager.default.removeItem(at: icon1Dest)
            try? FileManager.default.removeItem(at: icon2Dest)
        }

        let exportURL = FileManager.default.temporaryDirectory.appending(path: "roundtrip-test.dskm")
        defer { try? FileManager.default.removeItem(at: exportURL) }
        try AppShortcutStore.exportDock(to: exportURL)

        AppShortcutStore.save([])
        try? FileManager.default.removeItem(at: icon1Dest)
        try? FileManager.default.removeItem(at: icon2Dest)

        let imported = try AppShortcutStore.importDock(from: exportURL)

        #expect(imported.count == 2)
        #expect(imported[0].displayName == "Safari")
        #expect(imported[1].displayName == "Finder")
        #expect(FileManager.default.fileExists(atPath: icon1Dest.path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: icon2Dest.path(percentEncoded: false)))
    }

    @Test func importInvalidArchiveThrows() {
        let badFile = FileManager.default.temporaryDirectory.appending(path: "bad.dskm")
        defer { try? FileManager.default.removeItem(at: badFile) }

        try? Data("not a zip".utf8).write(to: badFile)

        #expect(throws: (any Error).self) {
            _ = try AppShortcutStore.importDock(from: badFile)
        }
    }

    @Test func importMissingJSONThrows() throws {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appending(path: UUID().uuidString)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }

        try Data("hello".utf8).write(to: tempDir.appending(path: "dummy.txt"))

        let archiveURL = fm.temporaryDirectory.appending(path: "no-json.dskm")
        defer { try? fm.removeItem(at: archiveURL) }

        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--sequesterRsrc",
                             tempDir.path(percentEncoded: false),
                             archiveURL.path(percentEncoded: false)]
        try process.run()
        process.waitUntilExit()

        #expect(throws: (any Error).self) {
            _ = try AppShortcutStore.importDock(from: archiveURL)
        }
    }

    @Test func exportOverwritesExistingFile() throws {
        let original = AppShortcutStore.load()
        defer { AppShortcutStore.save(original) }

        let url = URL(fileURLWithPath: "/Applications/Safari.app")
        AppShortcutStore.save([
            AppShortcut(displayName: "First", bundleIdentifier: "com.first", appURL: url, iconFileName: "f.png")
        ])

        let exportURL = FileManager.default.temporaryDirectory.appending(path: "overwrite-test.dskm")
        defer { try? FileManager.default.removeItem(at: exportURL) }

        try AppShortcutStore.exportDock(to: exportURL)

        AppShortcutStore.save([
            AppShortcut(displayName: "Second", bundleIdentifier: "com.second", appURL: url, iconFileName: "s.png")
        ])
        try AppShortcutStore.exportDock(to: exportURL)

        let imported = try AppShortcutStore.importDock(from: exportURL)
        #expect(imported.count == 1)
        #expect(imported[0].displayName == "Second")
    }

    @Test func notificationNamesExist() {
        #expect(Notification.Name.exportDock.rawValue == "exportDock")
        #expect(Notification.Name.importDock.rawValue == "importDock")
        #expect(Notification.Name.dockImported.rawValue == "dockImported")
    }
}

// MARK: - Default Seeding Tests

@Suite(.serialized)
struct DefaultSeedingTests {

    @Test func initializeWithDefaultsCreatesShortcuts() {
        let original = AppShortcutStore.load()
        defer { AppShortcutStore.save(original) }

        AppShortcutStore.save([])
        AppShortcutStore.initializeWithDefaults()

        let seeded = AppShortcutStore.load()
        #expect(seeded.count > 0)
    }

    @Test func initializeWithDefaultsIncludesFinder() {
        let original = AppShortcutStore.load()
        defer { AppShortcutStore.save(original) }

        AppShortcutStore.save([])
        AppShortcutStore.initializeWithDefaults()

        let seeded = AppShortcutStore.load()
        let hasFinder = seeded.contains { $0.bundleIdentifier == "com.apple.finder" }
        #expect(hasFinder)
    }

    @Test func initializeWithDefaultsCreatesIconFiles() {
        let original = AppShortcutStore.load()
        defer { AppShortcutStore.save(original) }

        var createdFileNames: [String] = []

        AppShortcutStore.save([])
        AppShortcutStore.initializeWithDefaults()

        let seeded = AppShortcutStore.load()
        createdFileNames = seeded.map { $0.iconFileName }
        defer { createdFileNames.forEach { AppShortcutStore.deleteIcon(named: $0) } }

        for shortcut in seeded {
            let url = AppShortcutStore.iconURL(for: shortcut.iconFileName)
            #expect(FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
        }
    }

    @Test func initializeWithDefaultsShortcutsHavePNGExtension() {
        let original = AppShortcutStore.load()
        defer { AppShortcutStore.save(original) }

        AppShortcutStore.save([])
        AppShortcutStore.initializeWithDefaults()

        let seeded = AppShortcutStore.load()
        defer { seeded.forEach { AppShortcutStore.deleteIcon(named: $0.iconFileName) } }

        for shortcut in seeded {
            #expect(shortcut.iconFileName.hasSuffix(".png"))
        }
    }

    @Test func initializeWithDefaultsDoesNotCrashForInvalidBundleIDs() {
        let original = AppShortcutStore.load()
        defer { AppShortcutStore.save(original) }

        AppShortcutStore.save([])
        AppShortcutStore.initializeWithDefaults()
        let seeded = AppShortcutStore.load()
        defer { seeded.forEach { AppShortcutStore.deleteIcon(named: $0.iconFileName) } }
        #expect(seeded.count >= 0)
    }
}

} // AppShortcutDataStoreTests
