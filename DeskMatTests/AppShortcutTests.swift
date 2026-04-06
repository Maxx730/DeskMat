import Testing
import Foundation
import AppKit
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
