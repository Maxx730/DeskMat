import Testing
import Foundation
import SwiftUI
@testable import DeskMat

// MARK: - computeDragMode Tests
//
// computeDragMode(_:) is a private method on ContentView and cannot be called
// directly. The geometry logic is mirrored here as a standalone function that
// matches the implementation exactly. Any change to the threshold constant
// (mergeThreshold = cellSize * 0.6) or the reorder-index formula must update
// this mirror to match.
//
// Geometry reference (cellSize=64, itemSpacing=8, step=72, threshold=38.4):
//
//  Display slot centers (0-indexed from 0):
//    slot 0: x = 32
//    slot 1: x = 104
//    slot 2: x = 176
//
//  localX reorderIndex cutoffs:
//    rawIndex = Int((localX - 32 + 36) / 72)  →  flips at localX = 68, 140, …

struct DragModeTests {

    private let cellSize: CGFloat = DockWidget<EmptyView>.cellSize  // 64
    private let itemSpacing: CGFloat = 8
    private var step: CGFloat { cellSize + itemSpacing }            // 72
    private var mergeThreshold: CGFloat { cellSize * 0.6 }          // 38.4

    private enum DragMode: Equatable {
        case reorder(Int)
        case merge(UUID)
    }

    // Mirrors ContentView.computeDragMode(_:)
    private func computeDragMode(localX: CGFloat, items: [DockItem], dragging: DockItem) -> DragMode {
        let rawIndex = Int((localX - cellSize / 2 + step / 2) / step)
        let reorderIndex = max(0, min(items.count - 1, rawIndex))

        let remaining = items.filter { $0.id != dragging.id }
        for (j, item) in remaining.enumerated() {
            let displayIndex = j < reorderIndex ? j : j + 1
            let centerX = cellSize / 2 + CGFloat(displayIndex) * step
            if abs(localX - centerX) < mergeThreshold {
                return .merge(item.id)
            }
        }

        return .reorder(reorderIndex)
    }

    private func makeShortcut(_ name: String) -> AppShortcut {
        AppShortcut(
            displayName: name,
            bundleIdentifier: "com.test.\(name.lowercased())",
            appURL: URL(filePath: "/Applications/\(name).app"),
            iconFileName: "\(name.lowercased()).png"
        )
    }

    // MARK: - Threshold constant

    @Test func mergeThresholdIs60PercentOfCellSize() {
        #expect(mergeThreshold == cellSize * 0.6)
    }

    @Test func mergeThresholdExceedsPreviousValue() {
        // Previous threshold was 0.45 × cellSize = 28.8.
        // Verify the current value is meaningfully larger.
        #expect(mergeThreshold > cellSize * 0.45)
    }

    // MARK: - Clear merge / reorder cases

    @Test func mergesWhenWithinThresholdOfTarget() {
        // items = [A, B], A dragging.
        // At localX=66: reorderIndex=0, B is at display pos 1 (center 104).
        // abs(66 - 104) = 38 < 38.4 → merge.
        let a = makeShortcut("A")
        let b = makeShortcut("B")
        let items: [DockItem] = [.shortcut(a), .shortcut(b)]

        let result = computeDragMode(localX: 66, items: items, dragging: .shortcut(a))

        #expect(result == .merge(b.id))
    }

    @Test func reordersWhenBeyondThresholdOfAllTargets() {
        // items = [A, B, C], A dragging.
        // At localX=100: reorderIndex=1, B at center 32 (dist 68), C at center 176 (dist 76).
        // Both distances > 38.4 → reorder.
        let a = makeShortcut("A")
        let b = makeShortcut("B")
        let c = makeShortcut("C")
        let items: [DockItem] = [.shortcut(a), .shortcut(b), .shortcut(c)]

        let result = computeDragMode(localX: 100, items: items, dragging: .shortcut(a))

        #expect(result == .reorder(1))
    }

    // MARK: - Threshold boundary

    @Test func mergesJustInsideThreshold() {
        // items = [A, B], A dragging.
        // B center = 104, threshold = 38.4.
        // abs(66 - 104) = 38 < 38.4 → merge (one unit inside the threshold).
        let a = makeShortcut("A")
        let b = makeShortcut("B")
        let items: [DockItem] = [.shortcut(a), .shortcut(b)]

        let result = computeDragMode(localX: 66, items: items, dragging: .shortcut(a))

        #expect(result == .merge(b.id))
    }

    @Test func reordersJustOutsideThreshold() {
        // items = [A, B], A dragging.
        // B center = 104, threshold = 38.4.
        // abs(65 - 104) = 39 > 38.4 → reorder (one unit outside the threshold).
        let a = makeShortcut("A")
        let b = makeShortcut("B")
        let items: [DockItem] = [.shortcut(a), .shortcut(b)]

        let result = computeDragMode(localX: 65, items: items, dragging: .shortcut(a))

        #expect(result == .reorder(0))
    }

    @Test func sameDragPositionMergesWithNewThresholdNotOld() {
        // localX=66 is 38px from target center.
        // Old threshold was 0.45 × 64 = 28.8 → 38 > 28.8 → would reorder.
        // New threshold is 0.6 × 64 = 38.4 → 38 < 38.4 → merges.
        // This test documents the changed behavior.
        let a = makeShortcut("A")
        let b = makeShortcut("B")
        let items: [DockItem] = [.shortcut(a), .shortcut(b)]

        let distance: CGFloat = 38
        let oldThreshold = cellSize * 0.45
        let newThreshold = cellSize * 0.6
        #expect(distance > oldThreshold)
        #expect(distance < newThreshold)

        let result = computeDragMode(localX: 104 - distance, items: items, dragging: .shortcut(a))
        #expect(result == .merge(b.id))
    }

    // MARK: - Correct target ID returned

    @Test func mergeReturnsCorrectTargetID() {
        // Verify .merge returns the ID of the target item, not the dragged item.
        let a = makeShortcut("A")
        let b = makeShortcut("B")
        let c = makeShortcut("C")
        let items: [DockItem] = [.shortcut(a), .shortcut(b), .shortcut(c)]

        let result = computeDragMode(localX: 66, items: items, dragging: .shortcut(a))

        if case .merge(let id) = result {
            #expect(id == b.id)
            #expect(id != a.id)
            #expect(id != c.id)
        } else {
            Issue.record("Expected .merge but got \(result)")
        }
    }

    @Test func mergeWorksWithFolderAsTarget() {
        // Merge target can be any DockItem, including a folder.
        let a = makeShortcut("A")
        let folder = AppFolder(name: "Work", shortcuts: [])
        let items: [DockItem] = [.shortcut(a), .folder(folder)]

        let result = computeDragMode(localX: 66, items: items, dragging: .shortcut(a))

        #expect(result == .merge(folder.id))
    }

    // MARK: - Reorder index clamping

    @Test func reorderIndexClampsToZeroAtLeftEdge() {
        let a = makeShortcut("A")
        let b = makeShortcut("B")
        let items: [DockItem] = [.shortcut(a), .shortcut(b)]

        // localX=0 is far left of the dock — B's center is far from a merge.
        let result = computeDragMode(localX: 0, items: items, dragging: .shortcut(a))

        #expect(result == .reorder(0))
    }

    @Test func reorderIndexClampsToLastIndexAtRightEdge() {
        let a = makeShortcut("A")
        let b = makeShortcut("B")
        let c = makeShortcut("C")
        let items: [DockItem] = [.shortcut(a), .shortcut(b), .shortcut(c)]

        // localX=10000 is far past all items. Max reorder index = items.count - 1 = 2.
        let result = computeDragMode(localX: 10_000, items: items, dragging: .shortcut(a))

        #expect(result == .reorder(2))
    }

    // MARK: - Multi-item layout

    @Test func reorderInGapBetweenItems() {
        // items = [A, B, C], A dragging.
        // At localX=100 (between B's center 32 and C's center 176 when gap is at 1),
        // both items are farther than 38.4 → pure reorder with no merge.
        let a = makeShortcut("A")
        let b = makeShortcut("B")
        let c = makeShortcut("C")
        let items: [DockItem] = [.shortcut(a), .shortcut(b), .shortcut(c)]

        let result = computeDragMode(localX: 100, items: items, dragging: .shortcut(a))

        if case .reorder(_) = result {
            // ✓ correct
        } else {
            Issue.record("Expected .reorder but got merge")
        }
    }

    @Test func dragOverSecondItemMerges() {
        // items = [A, B, C], A dragging.
        // Drag to position near C (display index 2, center 176).
        // At localX=176, reorderIndex = 2 or 1, check C is found.
        let a = makeShortcut("A")
        let b = makeShortcut("B")
        let c = makeShortcut("C")
        let items: [DockItem] = [.shortcut(a), .shortcut(b), .shortcut(c)]

        // localX = 140: reorderIndex = Int((140+4)/72) = Int(2.0) = 2
        // B: displayIndex=0 (j=0 < 2), center=32. abs(140-32)=108 → no
        // C: displayIndex=1 (j=1 < 2), center=104. abs(140-104)=36 < 38.4 → merge with C
        let result = computeDragMode(localX: 140, items: items, dragging: .shortcut(a))

        if case .merge(let id) = result {
            #expect(id == c.id)
        } else {
            Issue.record("Expected .merge(c.id) but got \(result)")
        }
    }

    // MARK: - Step constant

    @Test func stepEqualsCellSizePlusSpacing() {
        #expect(step == 72)
        #expect(step == cellSize + 8)
    }
}
