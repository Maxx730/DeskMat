import Testing
import Foundation
import AppKit
@testable import DeskMat

// MARK: - ShortcutSheet Icon Reset Tests
//
// ShortcutSheet is a SwiftUI View — its @State properties and private methods
// cannot be accessed from unit tests. The logic is modelled here as a plain
// struct + free function that mirrors the implementation exactly.
//
// Key differences from FolderSheet:
//   hasCustomIcon = selectedIconURL != nil || (isEditing && selectedIconImage != nil)
//     → image alone only counts as "custom" when editing an existing shortcut;
//       for new shortcuts, a file URL must be present.
//
//   resetToAppIcon():
//     → guard: requires selectedAppURL ?? shortcut.appURL, early-returns if absent
//     → sets selectedIconImage via NSWorkspace.shared.icon(forFile:)
//     → clears selectedIconURL, sets iconChanged = true
//
//   saveExisting() icon-source priority: URL first, then image, then unchanged

private struct ShortcutIconState {
    var isEditing: Bool
    var selectedIconImage: NSImage?
    var selectedIconURL: URL?
    var iconChanged: Bool
    var selectedAppURL: URL?     // set when user picks an app
    var shortcutAppURL: URL?     // equivalent to shortcut?.appURL (loaded on appear)

    // Mirrors ShortcutSheet.hasCustomIcon
    var hasCustomIcon: Bool {
        selectedIconURL != nil || (isEditing && selectedIconImage != nil)
    }

    // Mirrors ShortcutSheet.resetToAppIcon()
    mutating func resetToAppIcon() {
        guard let appURL = selectedAppURL ?? shortcutAppURL else { return }
        selectedIconImage = NSWorkspace.shared.icon(forFile: appURL.path(percentEncoded: false))
        selectedIconURL = nil
        iconChanged = true
    }
}

// Mirrors the icon-source selection in ShortcutSheet.saveExisting().
// Returns which source would be used to write the icon file.
private enum IconSource: Equatable {
    case url(URL)
    case image        // NSImage — identity not compared, just presence
    case unchanged    // iconChanged == false: keep existing file
    case missing      // iconChanged but nothing to write (should not happen in practice)
}

private func resolveIconSource(
    iconChanged: Bool,
    selectedIconURL: URL?,
    selectedIconImage: NSImage?
) -> IconSource {
    guard iconChanged else { return .unchanged }
    if let url = selectedIconURL { return .url(url) }
    if selectedIconImage != nil  { return .image }
    return .missing
}

struct ShortcutSheetIconTests {

    // MARK: - hasCustomIcon — creating a new shortcut (isEditing = false)

    @Test func hasCustomIconFalseForNewShortcutWithNoURL() {
        let state = ShortcutIconState(
            isEditing: false, selectedIconImage: nil,
            selectedIconURL: nil, iconChanged: false
        )
        #expect(state.hasCustomIcon == false)
    }

    @Test func hasCustomIconTrueForNewShortcutWithURL() {
        let state = ShortcutIconState(
            isEditing: false, selectedIconImage: nil,
            selectedIconURL: URL(filePath: "/tmp/icon.png"), iconChanged: false
        )
        #expect(state.hasCustomIcon == true)
    }

    @Test func hasCustomIconFalseForNewShortcutWithImageButNoURL() {
        // When creating a new shortcut, a loaded image without a file URL is
        // the initial app icon — not a custom icon the user chose.
        let state = ShortcutIconState(
            isEditing: false, selectedIconImage: NSImage(),
            selectedIconURL: nil, iconChanged: false
        )
        #expect(state.hasCustomIcon == false)
    }

    // MARK: - hasCustomIcon — editing an existing shortcut (isEditing = true)

    @Test func hasCustomIconFalseForEditingWithNoImageAndNoURL() {
        let state = ShortcutIconState(
            isEditing: true, selectedIconImage: nil,
            selectedIconURL: nil, iconChanged: false
        )
        #expect(state.hasCustomIcon == false)
    }

    @Test func hasCustomIconTrueForEditingWithURL() {
        let state = ShortcutIconState(
            isEditing: true, selectedIconImage: nil,
            selectedIconURL: URL(filePath: "/tmp/icon.png"), iconChanged: false
        )
        #expect(state.hasCustomIcon == true)
    }

    @Test func hasCustomIconTrueForEditingWithImageOnly() {
        // When editing an existing shortcut, selectedIconImage is loaded from disk
        // on appear (no URL is stored). Image presence alone means "has custom icon".
        let state = ShortcutIconState(
            isEditing: true, selectedIconImage: NSImage(),
            selectedIconURL: nil, iconChanged: false
        )
        #expect(state.hasCustomIcon == true)
    }

    @Test func hasCustomIconTrueForEditingWithBothImageAndURL() {
        let state = ShortcutIconState(
            isEditing: true, selectedIconImage: NSImage(),
            selectedIconURL: URL(filePath: "/tmp/icon.png"), iconChanged: false
        )
        #expect(state.hasCustomIcon == true)
    }

    // MARK: - resetToAppIcon — state changes

    @Test func resetToAppIconClearsSelectedIconURL() {
        var state = ShortcutIconState(
            isEditing: true,
            selectedIconImage: NSImage(),
            selectedIconURL: URL(filePath: "/tmp/custom.png"),
            iconChanged: false,
            selectedAppURL: URL(filePath: "/Applications/Safari.app")
        )
        state.resetToAppIcon()
        #expect(state.selectedIconURL == nil)
    }

    @Test func resetToAppIconSetsIconChangedFlag() {
        var state = ShortcutIconState(
            isEditing: true,
            selectedIconImage: nil,
            selectedIconURL: URL(filePath: "/tmp/custom.png"),
            iconChanged: false,
            selectedAppURL: URL(filePath: "/Applications/Safari.app")
        )
        state.resetToAppIcon()
        #expect(state.iconChanged == true)
    }

    @Test func resetToAppIconSetsImageFromWorkspace() {
        // NSWorkspace.shared.icon(forFile:) always returns a non-nil NSImage
        // (falls back to a generic icon if the app is missing).
        // Using Finder which is guaranteed present on all macOS systems.
        var state = ShortcutIconState(
            isEditing: true,
            selectedIconImage: nil,
            selectedIconURL: nil,
            iconChanged: false,
            selectedAppURL: URL(filePath: "/System/Library/CoreServices/Finder.app")
        )
        state.resetToAppIcon()
        #expect(state.selectedIconImage != nil)
    }

    @Test func resetToAppIconPreferSelectedAppURLOverShortcutURL() {
        // selectedAppURL takes priority over shortcutAppURL (matches guard order).
        var state = ShortcutIconState(
            isEditing: true,
            selectedIconImage: nil,
            selectedIconURL: URL(filePath: "/tmp/custom.png"),
            iconChanged: false,
            selectedAppURL: URL(filePath: "/System/Library/CoreServices/Finder.app"),
            shortcutAppURL: URL(filePath: "/Applications/TextEdit.app")
        )
        state.resetToAppIcon()
        // Both paths produce an image; just confirm the call succeeded.
        #expect(state.selectedIconImage != nil)
        #expect(state.selectedIconURL == nil)
        #expect(state.iconChanged == true)
    }

    @Test func resetToAppIconFallsBackToShortcutAppURL() {
        // When selectedAppURL is nil, shortcutAppURL is used.
        var state = ShortcutIconState(
            isEditing: true,
            selectedIconImage: nil,
            selectedIconURL: URL(filePath: "/tmp/custom.png"),
            iconChanged: false,
            selectedAppURL: nil,
            shortcutAppURL: URL(filePath: "/System/Library/CoreServices/Finder.app")
        )
        state.resetToAppIcon()
        #expect(state.selectedIconImage != nil)
        #expect(state.selectedIconURL == nil)
        #expect(state.iconChanged == true)
    }

    // MARK: - resetToAppIcon — early return when no app URL

    @Test func resetToAppIconDoesNothingWhenNoAppURLAvailable() {
        // Guard: if neither selectedAppURL nor shortcutAppURL is set, return early.
        let originalImage = NSImage()
        let originalURL = URL(filePath: "/tmp/original.png")
        var state = ShortcutIconState(
            isEditing: true,
            selectedIconImage: originalImage,
            selectedIconURL: originalURL,
            iconChanged: false,
            selectedAppURL: nil,
            shortcutAppURL: nil
        )
        state.resetToAppIcon()
        // State must be completely unchanged.
        #expect(state.selectedIconURL == originalURL)
        #expect(state.iconChanged == false)
        #expect(state.selectedIconImage === originalImage)
    }

    // MARK: - hasCustomIcon after resetToAppIcon

    @Test func hasCustomIconFalseAfterResetForNewShortcut() {
        // New shortcut: after reset, URL is cleared → hasCustomIcon becomes false.
        var state = ShortcutIconState(
            isEditing: false,
            selectedIconImage: nil,
            selectedIconURL: URL(filePath: "/tmp/custom.png"),
            iconChanged: false,
            selectedAppURL: URL(filePath: "/System/Library/CoreServices/Finder.app")
        )
        #expect(state.hasCustomIcon == true)
        state.resetToAppIcon()
        // URL cleared, isEditing=false, so hasCustomIcon depends only on URL.
        #expect(state.hasCustomIcon == false)
    }

    @Test func hasCustomIconTrueAfterResetForEditingShortcut() {
        // Editing: after reset, URL is cleared but image is set from workspace
        // → isEditing=true && image!=nil → still has custom icon = true.
        var state = ShortcutIconState(
            isEditing: true,
            selectedIconImage: nil,
            selectedIconURL: URL(filePath: "/tmp/custom.png"),
            iconChanged: false,
            selectedAppURL: URL(filePath: "/System/Library/CoreServices/Finder.app")
        )
        state.resetToAppIcon()
        #expect(state.hasCustomIcon == true)
    }

    // MARK: - Save path: icon source resolution

    @Test func iconSourceUnchangedWhenIconNotChanged() {
        let source = resolveIconSource(iconChanged: false, selectedIconURL: nil, selectedIconImage: nil)
        #expect(source == .unchanged)
    }

    @Test func iconSourceUnchangedEvenWithURLWhenFlagIsFalse() {
        let source = resolveIconSource(
            iconChanged: false,
            selectedIconURL: URL(filePath: "/tmp/icon.png"),
            selectedIconImage: NSImage()
        )
        #expect(source == .unchanged)
    }

    @Test func iconSourceIsURLWhenChangedAndURLPresent() {
        let url = URL(filePath: "/tmp/icon.png")
        let source = resolveIconSource(iconChanged: true, selectedIconURL: url, selectedIconImage: NSImage())
        #expect(source == .url(url))
    }

    @Test func iconSourceIsImageWhenChangedAndURLClearedButImagePresent() {
        // This is the path taken after resetToAppIcon(): URL cleared, image set.
        let source = resolveIconSource(iconChanged: true, selectedIconURL: nil, selectedIconImage: NSImage())
        #expect(source == .image)
    }

    @Test func iconSourceIsMissingWhenChangedButNeitherURLNorImage() {
        // Edge case: should not occur in normal flow, but the resolution is safe.
        let source = resolveIconSource(iconChanged: true, selectedIconURL: nil, selectedIconImage: nil)
        #expect(source == .missing)
    }

    // MARK: - End-to-end flows

    @Test func resetFollowedBySaveUsesImageSource() {
        // Full flow: user opens edit sheet, taps reset icon, then saves.
        // After reset: URL=nil, image set from workspace, iconChanged=true.
        // Save path must choose .image, not .url.
        var state = ShortcutIconState(
            isEditing: true,
            selectedIconImage: NSImage(),
            selectedIconURL: URL(filePath: "/tmp/custom.png"),
            iconChanged: false,
            selectedAppURL: URL(filePath: "/System/Library/CoreServices/Finder.app")
        )

        state.resetToAppIcon()

        let source = resolveIconSource(
            iconChanged: state.iconChanged,
            selectedIconURL: state.selectedIconURL,
            selectedIconImage: state.selectedIconImage
        )
        #expect(source == .image)
    }

    @Test func pickCustomIconFollowedBySaveUsesURLSource() {
        // Full flow: user opens edit sheet, picks a custom icon file, then saves.
        var state = ShortcutIconState(
            isEditing: true, selectedIconImage: NSImage(),
            selectedIconURL: nil, iconChanged: false
        )

        // Simulate pickIcon(): sets URL, image, and flag.
        let pickedURL = URL(filePath: "/tmp/my-icon.png")
        state.selectedIconURL = pickedURL
        state.selectedIconImage = NSImage()
        state.iconChanged = true

        let source = resolveIconSource(
            iconChanged: state.iconChanged,
            selectedIconURL: state.selectedIconURL,
            selectedIconImage: state.selectedIconImage
        )
        #expect(source == .url(pickedURL))
    }

    @Test func editWithoutTouchingIconPreservesExistingSource() {
        // Editing name/label without changing the icon → iconChanged=false → .unchanged.
        let state = ShortcutIconState(
            isEditing: true, selectedIconImage: NSImage(),
            selectedIconURL: nil, iconChanged: false
        )
        let source = resolveIconSource(
            iconChanged: state.iconChanged,
            selectedIconURL: state.selectedIconURL,
            selectedIconImage: state.selectedIconImage
        )
        #expect(source == .unchanged)
    }
}
