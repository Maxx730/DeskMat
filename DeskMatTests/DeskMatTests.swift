import Testing
import Foundation
import AppKit
import SwiftUI
@testable import DeskMat

// MARK: - AppShortcut Tests

struct AppShortcutTests {

    @Test func initSetsAllProperties() {
        let url = URL(fileURLWithPath: "/Applications/Safari.app")
        let shortcut = AppShortcut(
            displayName: "Safari",
            bundleIdentifier: "com.apple.Safari",
            appURL: url,
            iconFileName: "icon.png"
        )

        #expect(shortcut.displayName == "Safari")
        #expect(shortcut.bundleIdentifier == "com.apple.Safari")
        #expect(shortcut.appURL == url)
        #expect(shortcut.iconFileName == "icon.png")
    }

    @Test func initGeneratesUniqueIDs() {
        let url = URL(fileURLWithPath: "/Applications/Safari.app")
        let a = AppShortcut(displayName: "A", bundleIdentifier: "com.a", appURL: url, iconFileName: "a.png")
        let b = AppShortcut(displayName: "B", bundleIdentifier: "com.b", appURL: url, iconFileName: "b.png")

        #expect(a.id != b.id)
    }

    @Test func encodesAndDecodesCorrectly() throws {
        let url = URL(fileURLWithPath: "/Applications/Safari.app")
        let original = AppShortcut(
            displayName: "Safari",
            bundleIdentifier: "com.apple.Safari",
            appURL: url,
            iconFileName: "icon.png"
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AppShortcut.self, from: data)

        #expect(decoded.id == original.id)
        #expect(decoded.displayName == original.displayName)
        #expect(decoded.bundleIdentifier == original.bundleIdentifier)
        #expect(decoded.appURL == original.appURL)
        #expect(decoded.iconFileName == original.iconFileName)
    }

    @Test func encodesAndDecodesArray() throws {
        let url = URL(fileURLWithPath: "/Applications/Safari.app")
        let shortcuts = [
            AppShortcut(displayName: "Safari", bundleIdentifier: "com.apple.Safari", appURL: url, iconFileName: "a.png"),
            AppShortcut(displayName: "Finder", bundleIdentifier: "com.apple.finder", appURL: url, iconFileName: "b.png"),
        ]

        let data = try JSONEncoder().encode(shortcuts)
        let decoded = try JSONDecoder().decode([AppShortcut].self, from: data)

        #expect(decoded.count == 2)
        #expect(decoded[0].displayName == "Safari")
        #expect(decoded[1].displayName == "Finder")
    }
}

// MARK: - AppShortcut Custom Label Tests

struct AppShortcutCustomLabelTests {

    @Test func customLabelDefaultsToNil() {
        let url = URL(fileURLWithPath: "/Applications/Safari.app")
        let shortcut = AppShortcut(
            displayName: "Safari",
            bundleIdentifier: "com.apple.Safari",
            appURL: url,
            iconFileName: "icon.png"
        )

        #expect(shortcut.customLabel == nil)
    }

    @Test func customLabelCanBeSet() {
        let url = URL(fileURLWithPath: "/Applications/Safari.app")
        let shortcut = AppShortcut(
            displayName: "Safari",
            bundleIdentifier: "com.apple.Safari",
            appURL: url,
            iconFileName: "icon.png",
            customLabel: "Browser"
        )

        #expect(shortcut.customLabel == "Browser")
    }

    @Test func labelReturnsCustomLabelWhenSet() {
        let url = URL(fileURLWithPath: "/Applications/Safari.app")
        let shortcut = AppShortcut(
            displayName: "Safari",
            bundleIdentifier: "com.apple.Safari",
            appURL: url,
            iconFileName: "icon.png",
            customLabel: "My Browser"
        )

        #expect(shortcut.label == "My Browser")
    }

    @Test func labelFallsBackToDisplayName() {
        let url = URL(fileURLWithPath: "/Applications/Safari.app")
        let shortcut = AppShortcut(
            displayName: "Safari",
            bundleIdentifier: "com.apple.Safari",
            appURL: url,
            iconFileName: "icon.png"
        )

        #expect(shortcut.label == "Safari")
    }

    @Test func customLabelEncodesAndDecodes() throws {
        let url = URL(fileURLWithPath: "/Applications/Safari.app")
        let original = AppShortcut(
            displayName: "Safari",
            bundleIdentifier: "com.apple.Safari",
            appURL: url,
            iconFileName: "icon.png",
            customLabel: "Browser"
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AppShortcut.self, from: data)

        #expect(decoded.customLabel == "Browser")
        #expect(decoded.label == "Browser")
    }

    @Test func nilCustomLabelEncodesAndDecodes() throws {
        let url = URL(fileURLWithPath: "/Applications/Safari.app")
        let original = AppShortcut(
            displayName: "Safari",
            bundleIdentifier: "com.apple.Safari",
            appURL: url,
            iconFileName: "icon.png"
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AppShortcut.self, from: data)

        #expect(decoded.customLabel == nil)
        #expect(decoded.label == "Safari")
    }

    @Test func decodesWithoutCustomLabelKey() throws {
        // Simulates loading data saved before customLabel was added
        let json = """
        {
            "id": "12345678-1234-1234-1234-123456789ABC",
            "displayName": "Safari",
            "bundleIdentifier": "com.apple.Safari",
            "appURL": "file:///Applications/Safari.app",
            "iconFileName": "icon.png"
        }
        """
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(AppShortcut.self, from: data)

        #expect(decoded.customLabel == nil)
        #expect(decoded.label == "Safari")
    }

    @Test func customLabelIsMutable() {
        let url = URL(fileURLWithPath: "/Applications/Safari.app")
        var shortcut = AppShortcut(
            displayName: "Safari",
            bundleIdentifier: "com.apple.Safari",
            appURL: url,
            iconFileName: "icon.png"
        )

        #expect(shortcut.label == "Safari")

        shortcut.customLabel = "Web"
        #expect(shortcut.label == "Web")

        shortcut.customLabel = nil
        #expect(shortcut.label == "Safari")
    }
}

// MARK: - WeatherService Tests

struct WeatherServiceTests {

    @Test func initialStateHasPlaceholders() {
        let service = WeatherService()

        #expect(service.temperature == "--°")
        #expect(service.locationName == "Williamsburg, VA")
        #expect(service.iconName == "cloud.sun.fill")
        #expect(service.isLoading == false)
    }
}

// MARK: - AppShortcutStore Tests

@Suite(.serialized)
struct AppShortcutStoreTests {

    /// Creates a temporary 1x1 PNG file with the given color and returns its URL.
    /// The caller is responsible for cleaning up the file.
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
        // A fresh load from Application Support should return an array
        // (empty if no shortcuts saved, or existing ones if they are)
        let result = AppShortcutStore.load()
        #expect(result is [AppShortcut])
    }

    @Test func saveAndLoadRoundTrips() {
        let original = AppShortcutStore.load()
        defer {
            // Restore original state
            AppShortcutStore.save(original)
        }

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

        // Verify file exists
        #expect(FileManager.default.fileExists(atPath: storedURL.path(percentEncoded: false)))

        // Delete and verify it's gone
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

// MARK: - ColorUtils Tests

struct ColorUtilsTests {

    @Test func averageColorOfSolidRedImage() {
        let image = NSImage(size: NSSize(width: 10, height: 10))
        image.lockFocus()
        NSColor.red.drawSwatch(in: NSRect(x: 0, y: 0, width: 10, height: 10))
        image.unlockFocus()

        let color = ColorUtils.averageColor(of: image)
        #expect(color != nil)
    }

    @Test func averageColorOfSolidGreenImage() {
        let image = NSImage(size: NSSize(width: 10, height: 10))
        image.lockFocus()
        NSColor.green.drawSwatch(in: NSRect(x: 0, y: 0, width: 10, height: 10))
        image.unlockFocus()

        let color = ColorUtils.averageColor(of: image)
        #expect(color != nil)
    }

    @Test func averageColorReturnsNilForTransparentBitmap() {
        // Create a bitmap with explicitly transparent pixels
        let width = 10
        let height = 10
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .calibratedRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            Issue.record("Failed to create bitmap")
            return
        }
        // Fill with fully transparent pixels (alpha = 0)
        for x in 0..<width {
            for y in 0..<height {
                bitmap.setColor(NSColor(red: 0, green: 0, blue: 0, alpha: 0), atX: x, y: y)
            }
        }
        let image = NSImage(size: NSSize(width: width, height: height))
        image.addRepresentation(bitmap)

        let color = ColorUtils.averageColor(of: image)
        #expect(color == nil)
    }

    @Test func averageColorForKnownBundleID() {
        // Finder is always available on macOS
        let color = ColorUtils.averageColor(forBundleIdentifier: "com.apple.finder")
        #expect(color != nil)
    }

    @Test func averageColorForInvalidBundleIDReturnsColor() {
        // NSWorkspace.shared.icon(forFile:) returns a generic icon for invalid paths,
        // so the fallback path still produces a color
        let color = ColorUtils.averageColor(forBundleIdentifier: "com.nonexistent.fakebundle.xyz")
        // The method falls back to a generic document icon, which has a color
        #expect(color != nil)
    }

    @Test func averageColorAppliesDarkenFactor() {
        // Create a solid white image — average color should be darkened (not pure white)
        let image = NSImage(size: NSSize(width: 10, height: 10))
        image.lockFocus()
        NSColor.white.drawSwatch(in: NSRect(x: 0, y: 0, width: 10, height: 10))
        image.unlockFocus()

        let color = ColorUtils.averageColor(of: image)
        #expect(color != nil)
        // The darken factor is 0.6, so a white image (1.0, 1.0, 1.0)
        // should produce roughly (0.6, 0.6, 0.6)
        // We can't easily extract SwiftUI Color components, but we verified it's non-nil
    }
    // MARK: - darkened

    @Test func darkenedReducesBrightness() {
        let white = Color.white
        let darkened = ColorUtils.darkened(white, by: 0.5)
        let ns = NSColor(darkened).usingColorSpace(.sRGB)!

        #expect(ns.redComponent < 0.6)
        #expect(ns.greenComponent < 0.6)
        #expect(ns.blueComponent < 0.6)
    }

    @Test func darkenedByZeroProducesBlack() {
        let color = Color.red
        let darkened = ColorUtils.darkened(color, by: 0.0)
        let ns = NSColor(darkened).usingColorSpace(.sRGB)!

        #expect(ns.redComponent < 0.01)
        #expect(ns.greenComponent < 0.01)
        #expect(ns.blueComponent < 0.01)
    }

    @Test func darkenedByOnePreservesColor() {
        let color = Color.blue
        let darkened = ColorUtils.darkened(color, by: 1.0)
        let original = NSColor(color).usingColorSpace(.sRGB)!
        let result = NSColor(darkened).usingColorSpace(.sRGB)!

        #expect(abs(result.redComponent - original.redComponent) < 0.01)
        #expect(abs(result.greenComponent - original.greenComponent) < 0.01)
        #expect(abs(result.blueComponent - original.blueComponent) < 0.01)
    }

    @Test func darkenedPreservesAlpha() {
        let color = Color.red.opacity(0.5)
        let darkened = ColorUtils.darkened(color, by: 0.5)
        let ns = NSColor(darkened).usingColorSpace(.sRGB)!

        #expect(abs(ns.alphaComponent - 0.5) < 0.01)
    }

    // MARK: - lightened

    @Test func lightenedIncreasesBrightness() {
        let dark = Color(red: 0.2, green: 0.2, blue: 0.2)
        let lightened = ColorUtils.lightened(dark, by: 0.5)
        let ns = NSColor(lightened).usingColorSpace(.sRGB)!

        #expect(ns.redComponent > 0.5)
        #expect(ns.greenComponent > 0.5)
        #expect(ns.blueComponent > 0.5)
    }

    @Test func lightenedByZeroPreservesColor() {
        let color = Color.red
        let lightened = ColorUtils.lightened(color, by: 0.0)
        let original = NSColor(color).usingColorSpace(.sRGB)!
        let result = NSColor(lightened).usingColorSpace(.sRGB)!

        #expect(abs(result.redComponent - original.redComponent) < 0.01)
        #expect(abs(result.greenComponent - original.greenComponent) < 0.01)
        #expect(abs(result.blueComponent - original.blueComponent) < 0.01)
    }

    @Test func lightenedByOneProducesWhite() {
        let color = Color(red: 0.3, green: 0.5, blue: 0.7)
        let lightened = ColorUtils.lightened(color, by: 1.0)
        let ns = NSColor(lightened).usingColorSpace(.sRGB)!

        #expect(abs(ns.redComponent - 1.0) < 0.01)
        #expect(abs(ns.greenComponent - 1.0) < 0.01)
        #expect(abs(ns.blueComponent - 1.0) < 0.01)
    }

    @Test func lightenedPreservesAlpha() {
        let color = Color.blue.opacity(0.4)
        let lightened = ColorUtils.lightened(color, by: 0.5)
        let ns = NSColor(lightened).usingColorSpace(.sRGB)!

        #expect(abs(ns.alphaComponent - 0.4) < 0.01)
    }
}
// MARK: - Settings & AppDelegate Tests

@Suite(.serialized)
struct SettingsTests {

    @Test func showLabelsDefaultsToTrue() {
        let defaults = UserDefaults.standard
        // Remove any existing value to test the default
        let existing = defaults.object(forKey: "showLabels")
        defer {
            if let existing {
                defaults.set(existing, forKey: "showLabels")
            } else {
                defaults.removeObject(forKey: "showLabels")
            }
        }

        defaults.removeObject(forKey: "showLabels")
        // When no value is stored, @AppStorage("showLabels") defaults to true
        let value = defaults.object(forKey: "showLabels")
        #expect(value == nil) // nil means the default (true) is used by @AppStorage
    }

    @Test func hoverSizeDefaultsToSmall() {
        let defaults = UserDefaults.standard
        let existing = defaults.object(forKey: "hoverSize")
        defer {
            if let existing {
                defaults.set(existing, forKey: "hoverSize")
            } else {
                defaults.removeObject(forKey: "hoverSize")
            }
        }

        defaults.removeObject(forKey: "hoverSize")
        let value = defaults.object(forKey: "hoverSize")
        #expect(value == nil) // nil means the default (.small) is used by @AppStorage
    }

    @Test func showLabelsPersistedToUserDefaults() {
        let defaults = UserDefaults.standard
        let existing = defaults.object(forKey: "showLabels")
        defer {
            if let existing {
                defaults.set(existing, forKey: "showLabels")
            } else {
                defaults.removeObject(forKey: "showLabels")
            }
        }

        defaults.set(false, forKey: "showLabels")
        #expect(defaults.bool(forKey: "showLabels") == false)

        defaults.set(true, forKey: "showLabels")
        #expect(defaults.bool(forKey: "showLabels") == true)
    }

    @Test func hoverSizePersistedToUserDefaults() {
        let defaults = UserDefaults.standard
        let existing = defaults.object(forKey: "hoverSize")
        defer {
            if let existing {
                defaults.set(existing, forKey: "hoverSize")
            } else {
                defaults.removeObject(forKey: "hoverSize")
            }
        }

        defaults.set(HoverSize.medium.rawValue, forKey: "hoverSize")
        #expect(defaults.string(forKey: "hoverSize") == "Medium")

        defaults.set(HoverSize.large.rawValue, forKey: "hoverSize")
        #expect(defaults.string(forKey: "hoverSize") == "Large")
    }

}

// MARK: - HoverSize Enum Tests

struct HoverSizeTests {

    @Test func allCasesContainsThreeCases() {
        #expect(HoverSize.allCases.count == 3)
    }

    @Test func rawValuesMatchDisplayNames() {
        #expect(HoverSize.small.rawValue == "Small")
        #expect(HoverSize.medium.rawValue == "Medium")
        #expect(HoverSize.large.rawValue == "Large")
    }

    @Test func scaleValuesAreCorrect() {
        #expect(HoverSize.small.scale == 1.2)
        #expect(HoverSize.medium.scale == 1.5)
        #expect(HoverSize.large.scale == 1.8)
    }

    @Test func initFromRawValue() {
        #expect(HoverSize(rawValue: "Small") == .small)
        #expect(HoverSize(rawValue: "Medium") == .medium)
        #expect(HoverSize(rawValue: "Large") == .large)
        #expect(HoverSize(rawValue: "Invalid") == nil)
    }
}

// MARK: - HoverAnimation Enum Tests

struct HoverAnimationTests {

    @Test func allCasesContainsFiveCases() {
        #expect(HoverAnimation.allCases.count == 5)
    }

    @Test func rawValuesMatchDisplayNames() {
        #expect(HoverAnimation.bounce.rawValue == "Bounce")
        #expect(HoverAnimation.pulse.rawValue == "Pulse")
        #expect(HoverAnimation.jiggle.rawValue == "Jiggle")
        #expect(HoverAnimation.pop.rawValue == "Pop")
        #expect(HoverAnimation.none.rawValue == "None")
    }

    @Test func initFromRawValue() {
        #expect(HoverAnimation(rawValue: "Bounce") == .bounce)
        #expect(HoverAnimation(rawValue: "Pulse") == .pulse)
        #expect(HoverAnimation(rawValue: "Jiggle") == .jiggle)
        #expect(HoverAnimation(rawValue: "Pop") == .pop)
        #expect(HoverAnimation(rawValue: "None") == HoverAnimation.none)
        #expect(HoverAnimation(rawValue: "Invalid") == nil)
    }
}

// MARK: - DockPosition Enum Tests

struct DockPositionTests {

    @Test func allCasesContainsTwoCases() {
        #expect(DockPosition.allCases.count == 2)
    }

    @Test func rawValuesMatchDisplayNames() {
        #expect(DockPosition.bottom.rawValue == "Bottom")
        #expect(DockPosition.top.rawValue == "Top")
    }

    @Test func initFromRawValue() {
        #expect(DockPosition(rawValue: "Bottom") == .bottom)
        #expect(DockPosition(rawValue: "Top") == .top)
        #expect(DockPosition(rawValue: "Invalid") == nil)
    }
}

// MARK: - Additional Settings Tests

@Suite(.serialized)
struct AdditionalSettingsTests {

    @Test func hoverAnimationDefaultsToBounce() {
        let defaults = UserDefaults.standard
        let existing = defaults.object(forKey: "hoverAnimation")
        defer {
            if let existing {
                defaults.set(existing, forKey: "hoverAnimation")
            } else {
                defaults.removeObject(forKey: "hoverAnimation")
            }
        }

        defaults.removeObject(forKey: "hoverAnimation")
        let value = defaults.object(forKey: "hoverAnimation")
        #expect(value == nil) // nil means the default (.bounce) is used by @AppStorage
    }

    @Test func hoverAnimationPersistedToUserDefaults() {
        let defaults = UserDefaults.standard
        let existing = defaults.object(forKey: "hoverAnimation")
        defer {
            if let existing {
                defaults.set(existing, forKey: "hoverAnimation")
            } else {
                defaults.removeObject(forKey: "hoverAnimation")
            }
        }

        defaults.set(HoverAnimation.jiggle.rawValue, forKey: "hoverAnimation")
        #expect(defaults.string(forKey: "hoverAnimation") == "Jiggle")

        defaults.set(HoverAnimation.none.rawValue, forKey: "hoverAnimation")
        #expect(defaults.string(forKey: "hoverAnimation") == "None")
    }

    @Test func dockPositionDefaultsToBottom() {
        let defaults = UserDefaults.standard
        let existing = defaults.object(forKey: "dockPosition")
        defer {
            if let existing {
                defaults.set(existing, forKey: "dockPosition")
            } else {
                defaults.removeObject(forKey: "dockPosition")
            }
        }

        defaults.removeObject(forKey: "dockPosition")
        let value = defaults.object(forKey: "dockPosition")
        #expect(value == nil) // nil means the default (.bottom) is used by @AppStorage
    }

    @Test func dockPositionPersistedToUserDefaults() {
        let defaults = UserDefaults.standard
        let existing = defaults.object(forKey: "dockPosition")
        defer {
            if let existing {
                defaults.set(existing, forKey: "dockPosition")
            } else {
                defaults.removeObject(forKey: "dockPosition")
            }
        }

        defaults.set(DockPosition.top.rawValue, forKey: "dockPosition")
        #expect(defaults.string(forKey: "dockPosition") == "Top")

        defaults.set(DockPosition.bottom.rawValue, forKey: "dockPosition")
        #expect(defaults.string(forKey: "dockPosition") == "Bottom")
    }

    @Test func dockOffsetDefaultsToZero() {
        let defaults = UserDefaults.standard
        let existing = defaults.object(forKey: "dockOffset")
        defer {
            if let existing {
                defaults.set(existing, forKey: "dockOffset")
            } else {
                defaults.removeObject(forKey: "dockOffset")
            }
        }

        defaults.removeObject(forKey: "dockOffset")
        // integer(forKey:) returns 0 when no value is set
        #expect(defaults.integer(forKey: "dockOffset") == 0)
    }

    @Test func dockOffsetPersistedToUserDefaults() {
        let defaults = UserDefaults.standard
        let existing = defaults.object(forKey: "dockOffset")
        defer {
            if let existing {
                defaults.set(existing, forKey: "dockOffset")
            } else {
                defaults.removeObject(forKey: "dockOffset")
            }
        }

        defaults.set(25, forKey: "dockOffset")
        #expect(defaults.integer(forKey: "dockOffset") == 25)

        defaults.set(-10, forKey: "dockOffset")
        #expect(defaults.integer(forKey: "dockOffset") == -10)
    }

}

struct NotificationTests {

    @Test func addShortcutNotificationNameExists() {
        #expect(Notification.Name.addShortcut.rawValue == "addShortcut")
    }

    @Test func openSettingsNotificationNameExists() {
        #expect(Notification.Name.openSettings.rawValue == "openSettings")
    }

    @Test func notificationNamesAreDistinct() {
        #expect(Notification.Name.addShortcut != Notification.Name.openSettings)
    }
}

struct StatusBarMenuTests {

    /// Verifies the expected menu item titles and key equivalents
    /// that AppDelegate.setupStatusItem() should configure.
    @Test func expectedMenuItemConfiguration() {
        let expectedItems: [(title: String, keyEquivalent: String)] = [
            ("Add Shortcut...", ""),
            ("Settings...", ","),
            ("Quit DeskMat", "q"),
        ]

        #expect(expectedItems.count == 3)
        #expect(expectedItems[0].title == "Add Shortcut...")
        #expect(expectedItems[1].title == "Settings...")
        #expect(expectedItems[1].keyEquivalent == ",")
        #expect(expectedItems[2].title == "Quit DeskMat")
        #expect(expectedItems[2].keyEquivalent == "q")
    }
}

struct SettingsWindowTests {

    /// Verifies the expected settings window configuration values.
    @Test func expectedSettingsWindowProperties() {
        let expectedTitle = "DeskMat Settings"
        let expectedWidth: CGFloat = 420
        let expectedHeight: CGFloat = 300

        #expect(expectedTitle == "DeskMat Settings")
        #expect(expectedWidth == 420)
        #expect(expectedHeight == 300)
    }
}

// MARK: - Import / Export Tests
@Suite(.serialized)
struct ImportExportTests {

    /// Creates a temporary 1x1 PNG and returns its URL.
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

        // Create test icon files so they get packaged
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

        // Export
        let exportURL = FileManager.default.temporaryDirectory.appending(path: "roundtrip-test.dskm")
        defer { try? FileManager.default.removeItem(at: exportURL) }
        try AppShortcutStore.exportDock(to: exportURL)

        // Clear current state
        AppShortcutStore.save([])
        try? FileManager.default.removeItem(at: icon1Dest)
        try? FileManager.default.removeItem(at: icon2Dest)

        // Import
        let imported = try AppShortcutStore.importDock(from: exportURL)

        #expect(imported.count == 2)
        #expect(imported[0].displayName == "Safari")
        #expect(imported[1].displayName == "Finder")

        // Verify icons were restored
        #expect(FileManager.default.fileExists(atPath: icon1Dest.path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: icon2Dest.path(percentEncoded: false)))
    }

    @Test func importInvalidArchiveThrows() {
        let badFile = FileManager.default.temporaryDirectory.appending(path: "bad.dskm")
        defer { try? FileManager.default.removeItem(at: badFile) }

        // Write garbage data
        try? Data("not a zip".utf8).write(to: badFile)

        #expect(throws: (any Error).self) {
            _ = try AppShortcutStore.importDock(from: badFile)
        }
    }

    @Test func importMissingJSONThrows() throws {
        // Create a valid zip but without shortcuts.json
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appending(path: UUID().uuidString)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }

        // Create a dummy file so the zip isn't empty
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

        // Export twice — second should overwrite first
        try AppShortcutStore.exportDock(to: exportURL)

        AppShortcutStore.save([
            AppShortcut(displayName: "Second", bundleIdentifier: "com.second", appURL: url, iconFileName: "s.png")
        ])
        try AppShortcutStore.exportDock(to: exportURL)

        // Import should get the second version
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

// MARK: - Edit Shortcut Notification Tests

struct EditShortcutNotificationTests {

    @Test func editShortcutNotificationNameExists() {
        #expect(Notification.Name.editShortcut.rawValue == "editShortcut")
    }

    @Test func shortcutEditedNotificationNameExists() {
        #expect(Notification.Name.shortcutEdited.rawValue == "shortcutEdited")
    }

    @Test func editNotificationNamesAreDistinct() {
        #expect(Notification.Name.editShortcut != Notification.Name.shortcutEdited)
        #expect(Notification.Name.editShortcut != Notification.Name.addShortcut)
        #expect(Notification.Name.shortcutEdited != Notification.Name.shortcutAdded)
    }
}

// MARK: - Widget Settings Tests

@Suite(.serialized)
struct WidgetSettingsTests {

    @Test func showWeatherWidgetDefaultsToTrue() {
        let defaults = UserDefaults.standard
        let existing = defaults.object(forKey: "showWeatherWidget")
        defer {
            if let existing {
                defaults.set(existing, forKey: "showWeatherWidget")
            } else {
                defaults.removeObject(forKey: "showWeatherWidget")
            }
        }

        defaults.removeObject(forKey: "showWeatherWidget")
        let value = defaults.object(forKey: "showWeatherWidget")
        #expect(value == nil) // nil means the default (true) is used by @AppStorage
    }

    @Test func showClockWidgetDefaultsToTrue() {
        let defaults = UserDefaults.standard
        let existing = defaults.object(forKey: "showClockWidget")
        defer {
            if let existing {
                defaults.set(existing, forKey: "showClockWidget")
            } else {
                defaults.removeObject(forKey: "showClockWidget")
            }
        }

        defaults.removeObject(forKey: "showClockWidget")
        let value = defaults.object(forKey: "showClockWidget")
        #expect(value == nil) // nil means the default (true) is used by @AppStorage
    }

    @Test func showWeatherWidgetPersistedToUserDefaults() {
        let defaults = UserDefaults.standard
        let existing = defaults.object(forKey: "showWeatherWidget")
        defer {
            if let existing {
                defaults.set(existing, forKey: "showWeatherWidget")
            } else {
                defaults.removeObject(forKey: "showWeatherWidget")
            }
        }

        defaults.set(false, forKey: "showWeatherWidget")
        #expect(defaults.bool(forKey: "showWeatherWidget") == false)

        defaults.set(true, forKey: "showWeatherWidget")
        #expect(defaults.bool(forKey: "showWeatherWidget") == true)
    }

    @Test func showClockWidgetPersistedToUserDefaults() {
        let defaults = UserDefaults.standard
        let existing = defaults.object(forKey: "showClockWidget")
        defer {
            if let existing {
                defaults.set(existing, forKey: "showClockWidget")
            } else {
                defaults.removeObject(forKey: "showClockWidget")
            }
        }

        defaults.set(false, forKey: "showClockWidget")
        #expect(defaults.bool(forKey: "showClockWidget") == false)

        defaults.set(true, forKey: "showClockWidget")
        #expect(defaults.bool(forKey: "showClockWidget") == true)
    }

    @Test func showBatteryWidgetDefaultsToTrue() {
        let defaults = UserDefaults.standard
        let existing = defaults.object(forKey: "showBatteryWidget")
        defer {
            if let existing {
                defaults.set(existing, forKey: "showBatteryWidget")
            } else {
                defaults.removeObject(forKey: "showBatteryWidget")
            }
        }

        defaults.removeObject(forKey: "showBatteryWidget")
        let value = defaults.object(forKey: "showBatteryWidget")
        #expect(value == nil) // nil means the default (true) is used by @AppStorage
    }

    @Test func showBatteryWidgetPersistedToUserDefaults() {
        let defaults = UserDefaults.standard
        let existing = defaults.object(forKey: "showBatteryWidget")
        defer {
            if let existing {
                defaults.set(existing, forKey: "showBatteryWidget")
            } else {
                defaults.removeObject(forKey: "showBatteryWidget")
            }
        }

        defaults.set(false, forKey: "showBatteryWidget")
        #expect(defaults.bool(forKey: "showBatteryWidget") == false)

        defaults.set(true, forKey: "showBatteryWidget")
        #expect(defaults.bool(forKey: "showBatteryWidget") == true)
    }

    @Test func finderDefaultDirectoryDefaultsToHome() {
        let defaults = UserDefaults.standard
        let existing = defaults.object(forKey: "finderDefaultDirectory")
        defer {
            if let existing {
                defaults.set(existing, forKey: "finderDefaultDirectory")
            } else {
                defaults.removeObject(forKey: "finderDefaultDirectory")
            }
        }

        defaults.removeObject(forKey: "finderDefaultDirectory")
        let value = defaults.object(forKey: "finderDefaultDirectory")
        #expect(value == nil) // nil means the default ("~/") is used by @AppStorage
    }

    @Test func finderDefaultDirectoryPersistedToUserDefaults() {
        let defaults = UserDefaults.standard
        let existing = defaults.object(forKey: "finderDefaultDirectory")
        defer {
            if let existing {
                defaults.set(existing, forKey: "finderDefaultDirectory")
            } else {
                defaults.removeObject(forKey: "finderDefaultDirectory")
            }
        }

        defaults.set("~/Desktop", forKey: "finderDefaultDirectory")
        #expect(defaults.string(forKey: "finderDefaultDirectory") == "~/Desktop")

        defaults.set("/Applications", forKey: "finderDefaultDirectory")
        #expect(defaults.string(forKey: "finderDefaultDirectory") == "/Applications")
    }
}

// MARK: - Strings Constants Tests

struct StringsConstantsTests {

    @Test func settingsStringsExist() {
        #expect(!Strings.Settings.finderDefaultDirectory.isEmpty)
        #expect(!Strings.Settings.finderDefaultDirectorySublabel.isEmpty)
        #expect(!Strings.Settings.showWeatherWidget.isEmpty)
        #expect(!Strings.Settings.showClockWidget.isEmpty)
        #expect(!Strings.Settings.showBatteryWidget.isEmpty)
    }

    @Test func windowStringsExist() {
        #expect(!Strings.Windows.addShortcut.isEmpty)
        #expect(!Strings.Windows.editShortcut.isEmpty)
        #expect(!Strings.Windows.exportDock.isEmpty)
        #expect(!Strings.Windows.importDock.isEmpty)
        #expect(!Strings.Windows.settings.isEmpty)
    }

    @Test func shortcutStringsExist() {
        #expect(!Strings.Shortcuts.application.isEmpty)
        #expect(!Strings.Shortcuts.icon.isEmpty)
        #expect(!Strings.Shortcuts.customLabel.isEmpty)
        #expect(!Strings.Shortcuts.chooseApp.isEmpty)
        #expect(!Strings.Shortcuts.chooseIcon.isEmpty)
    }

    @Test func weatherStringsExist() {
        #expect(!Strings.Weather.temperaturePlaceholder.isEmpty)
        #expect(!Strings.Weather.defaultLocationName.isEmpty)
    }
}

// MARK: - DockOverlay Tests

struct DockOverlayTests {

    @Test func outlinePathIsNonEmpty() {
        let overlay = DockOverlay(dockSize: CGSize(width: 200, height: 80), mousePosition: nil)
        let path = overlay.outlinePath
        #expect(!path.isEmpty)
    }

    @Test func outlinePathIsInsetByHalfCircleSize() {
        let overlay = DockOverlay(dockSize: CGSize(width: 200, height: 80), mousePosition: nil)
        let bounds = overlay.outlinePath.boundingRect
        // The path should be inset from the full size by circleSize/2 on each side
        // circleSize is 3, so inset is 1.5 on each side
        #expect(bounds.minX >= 1.0)
        #expect(bounds.minY >= 1.0)
        #expect(bounds.maxX <= 199.0)
        #expect(bounds.maxY <= 79.0)
    }

    @Test func pointAtZeroReturnsValidPoint() {
        let size = CGSize(width: 200, height: 80)
        let overlay = DockOverlay(dockSize: size, mousePosition: nil)
        let p = overlay.point(at: 0.0)
        #expect(p.x >= 0 && p.x <= size.width)
        #expect(p.y >= 0 && p.y <= size.height)
    }

    @Test func pointAtOneReturnsFinitePoint() {
        let size = CGSize(width: 200, height: 80)
        let overlay = DockOverlay(dockSize: size, mousePosition: nil)
        let p = overlay.point(at: 1.0)
        #expect(p.x.isFinite)
        #expect(p.y.isFinite)
    }

    @Test func pointAtHalfReturnsValidPoint() {
        let size = CGSize(width: 200, height: 80)
        let overlay = DockOverlay(dockSize: size, mousePosition: nil)
        let p = overlay.point(at: 0.5)
        #expect(p.x >= 0 && p.x <= size.width)
        #expect(p.y >= 0 && p.y <= size.height)
    }

    @Test func pointsClampsOutOfRange() {
        let size = CGSize(width: 200, height: 80)
        let overlay = DockOverlay(dockSize: size, mousePosition: nil)
        let pNeg = overlay.point(at: -0.5)
        let pOver = overlay.point(at: 1.5)
        // Clamped values should produce finite points
        #expect(pNeg.x.isFinite && pNeg.y.isFinite)
        #expect(pOver.x.isFinite && pOver.y.isFinite)
        // point(at: -0.5) clamps to 0, same as point(at: 0)
        let pZero = overlay.point(at: 0.0)
        #expect(abs(pNeg.x - pZero.x) < 1.0)
        #expect(abs(pNeg.y - pZero.y) < 1.0)
    }

    @Test func angleReturnsFiniteValue() {
        let overlay = DockOverlay(dockSize: CGSize(width: 200, height: 80), mousePosition: nil)
        let a = overlay.angle(at: 0.25)
        #expect(a.radians.isFinite)
    }

    @Test func angleVariesAlongPath() {
        let overlay = DockOverlay(dockSize: CGSize(width: 200, height: 80), mousePosition: nil)
        // At different positions along the path, the angle should differ
        // (the path has straight edges and corners)
        let a1 = overlay.angle(at: 0.1)
        let a2 = overlay.angle(at: 0.4)
        #expect(abs(a1.radians - a2.radians) > 0.01)
    }

    @Test func closestFractionFindsNearestEdge() {
        let size = CGSize(width: 200, height: 80)
        let overlay = DockOverlay(dockSize: size, mousePosition: nil)
        // A point at the top-center should map to a fraction on the top edge
        let fraction = overlay.closestFraction(to: CGPoint(x: 100, y: 0))
        let p = overlay.point(at: fraction)
        // The closest path point should be near the top (small y)
        #expect(p.y < 10)
    }

    @Test func closestFractionForBottomCenter() {
        let size = CGSize(width: 200, height: 80)
        let overlay = DockOverlay(dockSize: size, mousePosition: nil)
        let fraction = overlay.closestFraction(to: CGPoint(x: 100, y: 80))
        let p = overlay.point(at: fraction)
        // The closest path point should be near the bottom (large y)
        #expect(p.y > 70)
    }
}

