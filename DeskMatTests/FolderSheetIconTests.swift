import Testing
import Foundation
import AppKit
@testable import DeskMat

// MARK: - FolderSheet Icon Reset Tests
//
// FolderSheet is a SwiftUI View — its @State properties and private methods
// (hasCustomIcon, resetIcon, save) cannot be accessed from unit tests.
// The logic is modelled here as a plain struct + free function that mirrors
// the implementation exactly:
//
//   hasCustomIcon: Bool          { customIconImage != nil }
//   resetIcon()                  { customIconURL = nil; customIconImage = nil; iconChanged = true }
//   save() icon-resolution path  { iconChanged && customIconURL == nil → iconFileName = nil }

private struct FolderIconState {
    var customIconImage: NSImage?
    var customIconURL: URL?
    var iconChanged: Bool

    // Mirrors FolderSheet.hasCustomIcon
    var hasCustomIcon: Bool { customIconImage != nil }

    // Mirrors FolderSheet.resetIcon()
    mutating func resetIcon() {
        customIconURL = nil
        customIconImage = nil
        iconChanged = true
    }
}

// Mirrors the icon-filename resolution block inside FolderSheet.save().
// Returns the iconFileName that would be written to the saved AppFolder.
// AppShortcutStore.copyIcon (file I/O) is replaced by returning a sentinel
// string so we can verify the code path without touching the filesystem.
private func resolveIconFileName(
    existingFileName: String?,
    iconChanged: Bool,
    customIconURL: URL?
) -> String? {
    guard iconChanged else { return existingFileName }
    guard customIconURL != nil else { return nil }
    return "copied-icon.png" // sentinel: real code calls AppShortcutStore.copyIcon
}

struct FolderSheetIconTests {

    // MARK: - hasCustomIcon

    @Test func hasCustomIconFalseWhenImageIsNil() {
        let state = FolderIconState(customIconImage: nil, customIconURL: nil, iconChanged: false)
        #expect(state.hasCustomIcon == false)
    }

    @Test func hasCustomIconTrueWhenImageIsSet() {
        let state = FolderIconState(customIconImage: NSImage(), customIconURL: nil, iconChanged: false)
        #expect(state.hasCustomIcon == true)
    }

    @Test func hasCustomIconIgnoresURL() {
        // hasCustomIcon is driven only by customIconImage, not customIconURL.
        // A URL without an image (e.g., load failed) must not show the reset button.
        let stateWithURLOnly = FolderIconState(
            customIconImage: nil,
            customIconURL: URL(filePath: "/some/icon.png"),
            iconChanged: false
        )
        #expect(stateWithURLOnly.hasCustomIcon == false)
    }

    // MARK: - resetIcon

    @Test func resetIconClearsCustomImage() {
        var state = FolderIconState(customIconImage: NSImage(), customIconURL: nil, iconChanged: false)
        state.resetIcon()
        #expect(state.customIconImage == nil)
    }

    @Test func resetIconClearsCustomURL() {
        var state = FolderIconState(
            customIconImage: NSImage(),
            customIconURL: URL(filePath: "/tmp/icon.png"),
            iconChanged: false
        )
        state.resetIcon()
        #expect(state.customIconURL == nil)
    }

    @Test func resetIconSetsIconChangedFlag() {
        var state = FolderIconState(customIconImage: NSImage(), customIconURL: nil, iconChanged: false)
        state.resetIcon()
        #expect(state.iconChanged == true)
    }

    @Test func resetIconSetsIconChangedWhenItWasAlreadyTrue() {
        // Calling reset a second time must leave iconChanged = true.
        var state = FolderIconState(customIconImage: NSImage(), customIconURL: nil, iconChanged: true)
        state.resetIcon()
        #expect(state.iconChanged == true)
    }

    @Test func resetIconClearsBothImageAndURLTogether() {
        var state = FolderIconState(
            customIconImage: NSImage(),
            customIconURL: URL(filePath: "/tmp/icon.png"),
            iconChanged: false
        )
        state.resetIcon()
        #expect(state.customIconImage == nil)
        #expect(state.customIconURL == nil)
        #expect(state.iconChanged == true)
    }

    // MARK: - hasCustomIcon after reset

    @Test func hasCustomIconFalseAfterReset() {
        var state = FolderIconState(customIconImage: NSImage(), customIconURL: nil, iconChanged: false)
        #expect(state.hasCustomIcon == true)
        state.resetIcon()
        #expect(state.hasCustomIcon == false)
    }

    // MARK: - Save path: icon filename resolution

    @Test func saveWithNoIconChangePropagatesExistingFileName() {
        let resolved = resolveIconFileName(
            existingFileName: "folder-icon.png",
            iconChanged: false,
            customIconURL: nil
        )
        #expect(resolved == "folder-icon.png")
    }

    @Test func saveWithIconChangedAndNoURLProducesNilFileName() {
        // iconChanged=true + customIconURL=nil means the user cleared the icon.
        // The save path must store nil so the folder loses its custom icon.
        let resolved = resolveIconFileName(
            existingFileName: "old-icon.png",
            iconChanged: true,
            customIconURL: nil
        )
        #expect(resolved == nil)
    }

    @Test func saveWithIconChangedAndURLCopiesIcon() {
        let resolved = resolveIconFileName(
            existingFileName: nil,
            iconChanged: true,
            customIconURL: URL(filePath: "/tmp/new-icon.png")
        )
        #expect(resolved != nil)
    }

    @Test func saveWithNoChangePropagatesNilExistingFileName() {
        // Folder never had a custom icon — save without touching icon → stays nil.
        let resolved = resolveIconFileName(
            existingFileName: nil,
            iconChanged: false,
            customIconURL: nil
        )
        #expect(resolved == nil)
    }

    // MARK: - End-to-end: reset then save

    @Test func resetFollowedBySaveProducesNilIconFileName() {
        // Full flow: user opens an existing folder that has an icon,
        // taps reset, then saves. The saved folder must have iconFileName = nil.
        var state = FolderIconState(
            customIconImage: NSImage(),
            customIconURL: URL(filePath: "/existing/icon.png"),
            iconChanged: false
        )

        state.resetIcon()

        let resolvedFileName = resolveIconFileName(
            existingFileName: "existing-icon.png",
            iconChanged: state.iconChanged,
            customIconURL: state.customIconURL
        )
        #expect(resolvedFileName == nil)
    }

    @Test func pickIconFollowedBySaveProducesNonNilFileName() {
        // Full flow: user picks a new icon image then saves.
        var state = FolderIconState(customIconImage: nil, customIconURL: nil, iconChanged: false)

        // Simulate pickIcon(): sets URL, image, and flag.
        state.customIconURL = URL(filePath: "/new/icon.png")
        state.customIconImage = NSImage()
        state.iconChanged = true

        let resolvedFileName = resolveIconFileName(
            existingFileName: nil,
            iconChanged: state.iconChanged,
            customIconURL: state.customIconURL
        )
        #expect(resolvedFileName != nil)
    }

    @Test func noIconChangeFlagMeansExistingIconSurvivesSave() {
        // Editing a folder without touching the icon must preserve the existing file.
        let state = FolderIconState(
            customIconImage: NSImage(),
            customIconURL: nil,
            iconChanged: false   // user never touched the icon
        )

        let resolvedFileName = resolveIconFileName(
            existingFileName: "kept-icon.png",
            iconChanged: state.iconChanged,
            customIconURL: state.customIconURL
        )
        #expect(resolvedFileName == "kept-icon.png")
    }
}
