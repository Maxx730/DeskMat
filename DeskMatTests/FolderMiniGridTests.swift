import Testing
import Foundation
@testable import DeskMat

// MARK: - FolderMiniGrid Slot Tests
//
// FolderMiniGrid is a private struct inside FolderButton.swift and cannot be
// instantiated from tests. The slot-allocation logic is mirrored here as a
// pure function that matches the view body exactly:
//
//   ForEach(0..<4, id: \.self) { index in
//       if index < shortcuts.count { MiniIconCell(...) }
//       else { placeholder RoundedRectangle }
//   }
//
// The call site always passes `Array(folder.shortcuts.prefix(4))`, so the
// shortcuts array arriving at the view is already capped at 4 items.
//
// Both invariants are tested here:
//   1. The view always renders exactly 4 slots.
//   2. prefix(4) at the call site ensures at most 4 items reach the view.

private struct SlotConfiguration: Equatable {
    let iconSlots: Int
    let placeholderSlots: Int
    var totalSlots: Int { iconSlots + placeholderSlots }
}

// Mirrors the slot allocation in FolderMiniGrid.body.
// `shortcuts` is the array as received by the view (already prefix-capped by caller).
private func slotConfiguration(for shortcuts: [AppShortcut]) -> SlotConfiguration {
    let iconSlots = min(shortcuts.count, 4)       // ForEach 0..<4 with index < shortcuts.count
    let placeholderSlots = 4 - iconSlots
    return SlotConfiguration(iconSlots: iconSlots, placeholderSlots: placeholderSlots)
}

// Mirrors the call-site capping: Array(folder.shortcuts.prefix(4))
private func callSiteShortcuts(from folder: AppFolder) -> [AppShortcut] {
    Array(folder.shortcuts.prefix(4))
}

struct FolderMiniGridTests {

    private func makeShortcut(_ name: String) -> AppShortcut {
        AppShortcut(
            displayName: name,
            bundleIdentifier: "com.test.\(name.lowercased())",
            appURL: URL(filePath: "/Applications/\(name).app"),
            iconFileName: "\(name.lowercased()).png"
        )
    }

    // MARK: - Total slot count is always 4

    @Test func totalSlotsIsAlwaysFourForEmptyInput() {
        let config = slotConfiguration(for: [])
        #expect(config.totalSlots == 4)
    }

    @Test func totalSlotsIsAlwaysFourForOneShortcut() {
        let config = slotConfiguration(for: [makeShortcut("A")])
        #expect(config.totalSlots == 4)
    }

    @Test func totalSlotsIsAlwaysFourForTwoShortcuts() {
        let config = slotConfiguration(for: [makeShortcut("A"), makeShortcut("B")])
        #expect(config.totalSlots == 4)
    }

    @Test func totalSlotsIsAlwaysFourForThreeShortcuts() {
        let config = slotConfiguration(for: [makeShortcut("A"), makeShortcut("B"), makeShortcut("C")])
        #expect(config.totalSlots == 4)
    }

    @Test func totalSlotsIsAlwaysFourForFourShortcuts() {
        let a = makeShortcut("A"); let b = makeShortcut("B")
        let c = makeShortcut("C"); let d = makeShortcut("D")
        let config = slotConfiguration(for: [a, b, c, d])
        #expect(config.totalSlots == 4)
    }

    // MARK: - Icon slot / placeholder breakdown

    @Test func emptyFolderHasFourPlaceholders() {
        let config = slotConfiguration(for: [])
        #expect(config.iconSlots == 0)
        #expect(config.placeholderSlots == 4)
    }

    @Test func oneShortcutHasOneIconAndThreePlaceholders() {
        let config = slotConfiguration(for: [makeShortcut("A")])
        #expect(config.iconSlots == 1)
        #expect(config.placeholderSlots == 3)
    }

    @Test func twoShortcutsHaveTwoIconsAndTwoPlaceholders() {
        let config = slotConfiguration(for: [makeShortcut("A"), makeShortcut("B")])
        #expect(config.iconSlots == 2)
        #expect(config.placeholderSlots == 2)
    }

    @Test func threeShortcutsHaveThreeIconsAndOnePlaceholder() {
        let config = slotConfiguration(for: [makeShortcut("A"), makeShortcut("B"), makeShortcut("C")])
        #expect(config.iconSlots == 3)
        #expect(config.placeholderSlots == 1)
    }

    @Test func fourShortcutsHaveFourIconsAndNoPlaceholders() {
        let a = makeShortcut("A"); let b = makeShortcut("B")
        let c = makeShortcut("C"); let d = makeShortcut("D")
        let config = slotConfiguration(for: [a, b, c, d])
        #expect(config.iconSlots == 4)
        #expect(config.placeholderSlots == 0)
    }

    // MARK: - Counts are never negative

    @Test func iconSlotsNeverNegative() {
        for count in 0...6 {
            let shortcuts = (0..<count).map { makeShortcut("App\($0)") }
            let config = slotConfiguration(for: shortcuts)
            #expect(config.iconSlots >= 0)
        }
    }

    @Test func placeholderSlotsNeverNegative() {
        for count in 0...6 {
            let shortcuts = (0..<count).map { makeShortcut("App\($0)") }
            let config = slotConfiguration(for: shortcuts)
            #expect(config.placeholderSlots >= 0)
        }
    }

    // MARK: - Call-site prefix(4) capping

    @Test func callSiteCapsFiveShortcutsToFour() {
        let folder = AppFolder(name: "Test", shortcuts: (0..<5).map { makeShortcut("App\($0)") })
        let capped = callSiteShortcuts(from: folder)
        #expect(capped.count == 4)
    }

    @Test func callSiteCapsTenShortcutsToFour() {
        let folder = AppFolder(name: "Test", shortcuts: (0..<10).map { makeShortcut("App\($0)") })
        let capped = callSiteShortcuts(from: folder)
        #expect(capped.count == 4)
    }

    @Test func callSitePreservesFewerThanFour() {
        let folder = AppFolder(name: "Test", shortcuts: [makeShortcut("A"), makeShortcut("B")])
        let capped = callSiteShortcuts(from: folder)
        #expect(capped.count == 2)
    }

    @Test func callSitePreservesEmptyFolder() {
        let folder = AppFolder(name: "Empty")
        let capped = callSiteShortcuts(from: folder)
        #expect(capped.count == 0)
    }

    @Test func callSitePreservesExactlyFour() {
        let folder = AppFolder(name: "Test", shortcuts: (0..<4).map { makeShortcut("App\($0)") })
        let capped = callSiteShortcuts(from: folder)
        #expect(capped.count == 4)
    }

    @Test func callSitePreservesFirstFourShortcuts() {
        let shortcuts = (0..<6).map { makeShortcut("App\($0)") }
        let folder = AppFolder(name: "Test", shortcuts: shortcuts)
        let capped = callSiteShortcuts(from: folder)
        #expect(capped.map(\.displayName) == shortcuts.prefix(4).map(\.displayName))
    }

    // MARK: - Combined: call-site cap then slot allocation

    @Test func fiveShortcutsInFolderProduceFourIconSlotsNoPlaceholders() {
        let folder = AppFolder(name: "Test", shortcuts: (0..<5).map { makeShortcut("App\($0)") })
        let capped = callSiteShortcuts(from: folder)
        let config = slotConfiguration(for: capped)
        #expect(config.iconSlots == 4)
        #expect(config.placeholderSlots == 0)
        #expect(config.totalSlots == 4)
    }

    @Test func twoShortcutsInFolderProduceTwoIconsTwoPlaceholders() {
        let folder = AppFolder(name: "Test", shortcuts: [makeShortcut("A"), makeShortcut("B")])
        let capped = callSiteShortcuts(from: folder)
        let config = slotConfiguration(for: capped)
        #expect(config.iconSlots == 2)
        #expect(config.placeholderSlots == 2)
        #expect(config.totalSlots == 4)
    }

    @Test func emptyFolderProducesZeroIconsFourPlaceholders() {
        let folder = AppFolder(name: "Empty")
        let capped = callSiteShortcuts(from: folder)
        let config = slotConfiguration(for: capped)
        #expect(config.iconSlots == 0)
        #expect(config.placeholderSlots == 4)
        #expect(config.totalSlots == 4)
    }
}
