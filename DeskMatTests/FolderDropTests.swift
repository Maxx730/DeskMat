import Testing
import Foundation
@testable import DeskMat

// MARK: - commitFolderDrop Logic Tests
//
// commitFolderDrop is a private method on ContentView and cannot be called
// directly. The pure array-mutation logic is mirrored here as a standalone
// function. Any change to that algorithm must update this mirror to match.

struct FolderDropTests {

    // Mirrors ContentView.commitFolderDrop(shortcut:folder:at:)
    // Returns the mutated items array (sans save/dismiss side-effects).
    private func commitFolderDrop(
        items: [DockItem],
        shortcut: AppShortcut,
        folder: AppFolder,
        at dropIndex: Int
    ) -> [DockItem] {
        var items = items

        guard let folderItemIndex = items.firstIndex(where: {
            if case .folder(let f) = $0 { return f.id == folder.id }
            return false
        }) else { return items }

        guard case .folder(var sourceFolder) = items[folderItemIndex] else { return items }
        sourceFolder.shortcuts.removeAll { $0.id == shortcut.id }

        if sourceFolder.shortcuts.isEmpty {
            items.remove(at: folderItemIndex)
            let adjustedIndex = folderItemIndex < dropIndex ? dropIndex - 1 : dropIndex
            items.insert(.shortcut(shortcut), at: min(adjustedIndex, items.count))
        } else {
            items[folderItemIndex] = .folder(sourceFolder)
            items.insert(.shortcut(shortcut), at: min(dropIndex, items.count))
        }

        return items
    }

    private func makeShortcut(_ name: String) -> AppShortcut {
        AppShortcut(
            displayName: name,
            bundleIdentifier: "com.test.\(name.lowercased())",
            appURL: URL(filePath: "/Applications/\(name).app"),
            iconFileName: "\(name.lowercased()).png"
        )
    }

    // MARK: - Multi-shortcut folder (folder stays)

    @Test func dropsShortcutAndKeepsFolder() {
        let a = makeShortcut("A")
        let b = makeShortcut("B")
        let folder = AppFolder(name: "F", shortcuts: [a, b])
        let other = makeShortcut("Other")
        let items: [DockItem] = [.shortcut(other), .folder(folder)]

        let result = commitFolderDrop(items: items, shortcut: a, folder: folder, at: 0)

        // Folder still present with only B remaining
        let folderItem = result.first { if case .folder = $0 { return true }; return false }
        if case .folder(let f) = folderItem {
            #expect(f.shortcuts.count == 1)
            #expect(f.shortcuts[0].id == b.id)
        } else {
            Issue.record("Expected folder to remain")
        }
    }

    @Test func insertedAtCorrectIndexWhenFolderStays() {
        let a = makeShortcut("A")
        let b = makeShortcut("B")
        let folder = AppFolder(name: "F", shortcuts: [a, b])
        let other = makeShortcut("Other")
        // items = [Other, Folder] — drop A at index 0
        let items: [DockItem] = [.shortcut(other), .folder(folder)]

        let result = commitFolderDrop(items: items, shortcut: a, folder: folder, at: 0)

        if case .shortcut(let s) = result[0] {
            #expect(s.id == a.id)
        } else {
            Issue.record("Expected A at index 0")
        }
    }

    @Test func itemCountIncreasesWhenFolderStays() {
        let a = makeShortcut("A")
        let b = makeShortcut("B")
        let folder = AppFolder(name: "F", shortcuts: [a, b])
        let items: [DockItem] = [.folder(folder)]

        let result = commitFolderDrop(items: items, shortcut: a, folder: folder, at: 0)

        // Was 1 item (the folder); now 2 (folder + extracted shortcut)
        #expect(result.count == 2)
    }

    // MARK: - Single-shortcut folder (folder removed)

    @Test func removesEmptyFolderAfterDrop() {
        let a = makeShortcut("A")
        let folder = AppFolder(name: "F", shortcuts: [a])
        let items: [DockItem] = [.folder(folder)]

        let result = commitFolderDrop(items: items, shortcut: a, folder: folder, at: 0)

        let hasFolder = result.contains { if case .folder = $0 { return true }; return false }
        #expect(!hasFolder)
    }

    @Test func itemCountUnchangedWhenFolderRemoved() {
        // [Other, Folder(A)] → drop A → [Other, A] (folder gone, shortcut inserted)
        let a = makeShortcut("A")
        let folder = AppFolder(name: "F", shortcuts: [a])
        let other = makeShortcut("Other")
        let items: [DockItem] = [.shortcut(other), .folder(folder)]

        let result = commitFolderDrop(items: items, shortcut: a, folder: folder, at: 2)

        #expect(result.count == 2)
    }

    // MARK: - Drop index adjustment when folder is removed

    @Test func adjustsDropIndexWhenFolderRemovedBeforeDropPoint() {
        // [Other, Folder(A), X] — folder at index 1, drop at index 2
        // After removing folder: [Other, X]. Adjusted index = 2-1 = 1. Insert A at 1.
        let a = makeShortcut("A")
        let folder = AppFolder(name: "F", shortcuts: [a])
        let other = makeShortcut("Other")
        let x = makeShortcut("X")
        let items: [DockItem] = [.shortcut(other), .folder(folder), .shortcut(x)]

        let result = commitFolderDrop(items: items, shortcut: a, folder: folder, at: 2)

        if case .shortcut(let s) = result[1] {
            #expect(s.id == a.id)
        } else {
            Issue.record("Expected A at adjusted index 1, got \(result)")
        }
    }

    @Test func doesNotAdjustDropIndexWhenFolderRemovedAfterDropPoint() {
        // [Folder(A), Other, X] — folder at index 0, drop at index 0
        // After removing folder: [Other, X]. folderIndex(0) is NOT < dropIndex(0), no adjust.
        let a = makeShortcut("A")
        let folder = AppFolder(name: "F", shortcuts: [a])
        let other = makeShortcut("Other")
        let x = makeShortcut("X")
        let items: [DockItem] = [.folder(folder), .shortcut(other), .shortcut(x)]

        let result = commitFolderDrop(items: items, shortcut: a, folder: folder, at: 0)

        if case .shortcut(let s) = result[0] {
            #expect(s.id == a.id)
        } else {
            Issue.record("Expected A at index 0, got \(result)")
        }
    }

    @Test func dropAtEndClampsToItemCount() {
        let a = makeShortcut("A")
        let folder = AppFolder(name: "F", shortcuts: [a])
        let items: [DockItem] = [.folder(folder)]

        // Drop index beyond bounds — should clamp
        let result = commitFolderDrop(items: items, shortcut: a, folder: folder, at: 99)

        if case .shortcut(let s) = result.last {
            #expect(s.id == a.id)
        } else {
            Issue.record("Expected A at end")
        }
    }
}

// MARK: - crossDisplayItems Logic Tests

struct CrossDisplayItemsTests {

    // Mirrors ContentView.crossDisplayItems(dropAt:)
    private func crossDisplayItems(items: [DockItem], dropAt index: Int) -> [DockItem?] {
        var display = items.map { Optional($0) }
        let clamped = max(0, min(display.count, index))
        display.insert(nil, at: clamped)
        return display
    }

    private func makeShortcut(_ name: String) -> AppShortcut {
        AppShortcut(
            displayName: name,
            bundleIdentifier: "com.test.\(name.lowercased())",
            appURL: URL(filePath: "/Applications/\(name).app"),
            iconFileName: "\(name.lowercased()).png"
        )
    }

    @Test func insertsNilAtBeginning() {
        let a = makeShortcut("A")
        let b = makeShortcut("B")
        let items: [DockItem] = [.shortcut(a), .shortcut(b)]

        let result = crossDisplayItems(items: items, dropAt: 0)

        #expect(result.count == 3)
        #expect(result[0] == nil)
    }

    @Test func insertsNilAtEnd() {
        let a = makeShortcut("A")
        let b = makeShortcut("B")
        let items: [DockItem] = [.shortcut(a), .shortcut(b)]

        let result = crossDisplayItems(items: items, dropAt: 2)

        #expect(result.count == 3)
        #expect(result[2] == nil)
    }

    @Test func insertsNilInMiddle() {
        let a = makeShortcut("A")
        let b = makeShortcut("B")
        let c = makeShortcut("C")
        let items: [DockItem] = [.shortcut(a), .shortcut(b), .shortcut(c)]

        let result = crossDisplayItems(items: items, dropAt: 1)

        #expect(result.count == 4)
        #expect(result[1] == nil)
        if case .shortcut(let s) = result[0] { #expect(s.id == a.id) } else { Issue.record("Expected A at 0") }
        if case .shortcut(let s) = result[2] { #expect(s.id == b.id) } else { Issue.record("Expected B at 2") }
    }

    @Test func clampsNegativeIndexToZero() {
        let a = makeShortcut("A")
        let items: [DockItem] = [.shortcut(a)]

        let result = crossDisplayItems(items: items, dropAt: -5)

        #expect(result[0] == nil)
    }

    @Test func clampsBeyondEndToCount() {
        let a = makeShortcut("A")
        let items: [DockItem] = [.shortcut(a)]

        let result = crossDisplayItems(items: items, dropAt: 999)

        #expect(result.count == 2)
        #expect(result[1] == nil)
    }

    @Test func resultCountIsAlwaysItemsCountPlusOne() {
        let a = makeShortcut("A")
        let b = makeShortcut("B")
        let items: [DockItem] = [.shortcut(a), .shortcut(b)]

        for idx in [0, 1, 2, -1, 99] {
            let result = crossDisplayItems(items: items, dropAt: idx)
            #expect(result.count == items.count + 1)
        }
    }
}

// MARK: - DragCoordinator Drop Index Formula Tests
//
// DragCoordinator.handleMouseMoved is private. The drop index formula is
// mirrored here to verify the geometric calculation independently.

struct DragCoordinatorDropIndexTests {

    private let cellSize: CGFloat   = 64
    private let cellStep: CGFloat   = 72   // cellSize + 8pt spacing
    private let dockPadding: CGFloat = 10

    // Mirrors DragCoordinator.handleMouseMoved drop index calculation.
    private func dropIndex(screenX: CGFloat, dockMinX: CGFloat, itemCount: Int) -> Int {
        let localX = screenX - dockMinX - dockPadding
        let rawIndex = Int((localX - cellSize / 2 + cellStep / 2) / cellStep)
        return max(0, min(itemCount, rawIndex))
    }

    @Test func firstItemCenterMapsToIndexZero() {
        // First item center at dockMinX + padding + 32 = 0 + 10 + 32 = 42 in screen coords
        let screenX: CGFloat = 42    // dockMinX(0) + padding(10) + cellCenter(32)
        #expect(dropIndex(screenX: screenX, dockMinX: 0, itemCount: 3) == 0)
    }

    @Test func betweenFirstAndSecondMapsToIndexOne() {
        // Midpoint between slot 0 (32) and slot 1 (104) is 68. Past 68 → index 1.
        let screenX: CGFloat = 0 + 10 + 68 + 1   // dockMinX + padding + transition + 1
        #expect(dropIndex(screenX: screenX, dockMinX: 0, itemCount: 3) == 1)
    }

    @Test func clampsToZeroAtLeftEdge() {
        #expect(dropIndex(screenX: 0, dockMinX: 0, itemCount: 3) == 0)
    }

    @Test func clampsToItemCountAtRightEdge() {
        // Unlike reorder (clamps to count-1), cross-drag allows dropping AFTER last item
        let result = dropIndex(screenX: 100_000, dockMinX: 0, itemCount: 3)
        #expect(result == 3)
    }

    @Test func emptyDockAlwaysReturnsZero() {
        #expect(dropIndex(screenX: 500, dockMinX: 0, itemCount: 0) == 0)
    }

    @Test func nonZeroDockOriginIsAccountedFor() {
        // If dock starts at x=200, screenX=242 should map to first item center
        // localX = 242 - 200 - 10 = 32 → rawIndex = 0
        #expect(dropIndex(screenX: 242, dockMinX: 200, itemCount: 3) == 0)
    }
}
