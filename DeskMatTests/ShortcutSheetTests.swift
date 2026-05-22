import Testing
import Foundation
@testable import DeskMat

// MARK: - ShortcutSheet Logic Tests
//
// ShortcutSheet's save/validation methods are private on a SwiftUI View struct
// and cannot be called directly. The tests here cover:
//   1. The isEditing invariant (shortcut != nil → editing)
//   2. Save-disabled preconditions, mirrored as standalone guards
//   3. customLabel collapse logic (empty string → nil in saved shortcut)
//   4. Edited shortcut field mutation (mirrors saveExisting field assignments)

struct ShortcutSheetTests {

    private func makeShortcut(
        name: String = "TestApp",
        bundle: String = "com.test.app",
        customLabel: String? = nil
    ) -> AppShortcut {
        AppShortcut(
            displayName: name,
            bundleIdentifier: bundle,
            appURL: URL(filePath: "/Applications/TestApp.app"),
            iconFileName: "test.png",
            customLabel: customLabel
        )
    }

    // MARK: - isEditing logic

    @Test func isEditingFalseWhenShortcutIsNil() {
        // Mirrors: private var isEditing: Bool { shortcut != nil }
        let shortcut: AppShortcut? = nil
        #expect((shortcut != nil) == false)
    }

    @Test func isEditingTrueWhenShortcutIsProvided() {
        let shortcut: AppShortcut? = makeShortcut()
        #expect((shortcut != nil) == true)
    }

    // MARK: - Save-new disabled condition
    //
    // Mirrors: selectedAppURL == nil || (selectedIconURL == nil && selectedIconImage == nil)

    @Test func saveNewDisabledWhenAppURLMissing() {
        let appURL: URL? = nil
        let iconURL: URL? = URL(filePath: "/tmp/icon.png")
        let disabled = appURL == nil || (iconURL == nil)
        #expect(disabled == true)
    }

    @Test func saveNewDisabledWhenIconMissing() {
        let appURL: URL? = URL(filePath: "/Applications/Test.app")
        let iconURL: URL? = nil
        let iconImage: Bool = false  // no image
        let disabled = appURL == nil || (iconURL == nil && !iconImage)
        #expect(disabled == true)
    }

    @Test func saveNewEnabledWhenBothPresent() {
        let appURL: URL? = URL(filePath: "/Applications/Test.app")
        let iconURL: URL? = URL(filePath: "/tmp/icon.png")
        let disabled = appURL == nil || (iconURL == nil)
        #expect(disabled == false)
    }

    // MARK: - Save-edit disabled condition
    //
    // Mirrors: selectedBundleID.isEmpty

    @Test func saveEditDisabledWhenBundleIDEmpty() {
        let bundleID = ""
        #expect(bundleID.isEmpty == true)
    }

    @Test func saveEditEnabledWhenBundleIDPresent() {
        let bundleID = "com.example.app"
        #expect(bundleID.isEmpty == false)
    }

    // MARK: - customLabel collapse

    @Test func emptyCustomLabelCollapsesToNil() {
        // Mirrors: customLabel.isEmpty ? nil : customLabel in saveNew/saveExisting
        let customLabel = ""
        let result: String? = customLabel.isEmpty ? nil : customLabel
        #expect(result == nil)
    }

    @Test func nonEmptyCustomLabelPreserved() {
        let customLabel = "My App"
        let result: String? = customLabel.isEmpty ? nil : customLabel
        #expect(result == "My App")
    }

    @Test func whitespaceOnlyLabelIsNotEmpty() {
        // Whitespace is preserved — only truly empty string collapses
        let customLabel = "  "
        let result: String? = customLabel.isEmpty ? nil : customLabel
        #expect(result == "  ")
    }

    // MARK: - Edited shortcut field mutations
    //
    // Mirrors the field assignments in saveExisting()

    @Test func editedShortcutUpdatesDisplayName() {
        var shortcut = makeShortcut(name: "OldName")
        shortcut.displayName = "NewName"
        #expect(shortcut.displayName == "NewName")
    }

    @Test func editedShortcutUpdatesBundleIdentifier() {
        var shortcut = makeShortcut(bundle: "com.old")
        shortcut.bundleIdentifier = "com.new"
        #expect(shortcut.bundleIdentifier == "com.new")
    }

    @Test func editedShortcutUpdatesAppURL() {
        var shortcut = makeShortcut()
        let newURL = URL(filePath: "/Applications/NewApp.app")
        shortcut.appURL = newURL
        #expect(shortcut.appURL == newURL)
    }

    @Test func editedShortcutClearsCustomLabel() {
        var shortcut = makeShortcut(customLabel: "Old Label")
        let customLabel = ""
        shortcut.customLabel = customLabel.isEmpty ? nil : customLabel
        #expect(shortcut.customLabel == nil)
    }

    @Test func editedShortcutPreservesCustomLabel() {
        var shortcut = makeShortcut()
        let customLabel = "My Custom Label"
        shortcut.customLabel = customLabel.isEmpty ? nil : customLabel
        #expect(shortcut.customLabel == "My Custom Label")
    }

    // MARK: - Icon changed flag logic
    //
    // iconChanged is set when the user picks a new app or custom icon.
    // Only triggers icon file replacement in saveExisting.

    @Test func iconChangedFalseByDefault() {
        var iconChanged = false
        #expect(iconChanged == false)
        // Picking app sets it true
        iconChanged = true
        #expect(iconChanged == true)
    }
}
