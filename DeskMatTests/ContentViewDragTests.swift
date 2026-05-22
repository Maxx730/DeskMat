import Testing
import Foundation
import SwiftUI
@testable import DeskMat

// MARK: - ContentView Drag-to-Reorder Tests
//
// dragChanged(to:) and dragEnd() are private methods on ContentView (a SwiftUI
// View struct) and cannot be called directly from tests. The index calculation
// and array reorder logic are tested here as standalone functions that mirror
// the implementation exactly. Any change to those algorithms must update these
// tests to match.

struct ContentViewDragTests {

    private let cellSize: CGFloat = DockWidget<EmptyView>.cellSize   // 64
    private let dockOriginX: CGFloat = 10                             // horizontal padding

    // Mirrors dragChanged(to:) index calculation
    private func dragTargetIndex(positionX: CGFloat, count: Int) -> Int {
        let localX   = positionX - dockOriginX
        let rawIndex = Int((localX + cellSize / 4) / cellSize)
        return max(0, min(count - 1, rawIndex))
    }

    // Mirrors dragEnd() reorder commit
    private func commitReorder(display: [AppShortcut?], targetIndex: Int, dragging: AppShortcut) -> [AppShortcut] {
        var committed = display
        committed[targetIndex] = dragging
        return committed.compactMap { $0 }
    }

    private func makeShortcut(name: String) -> AppShortcut {
        AppShortcut(
            displayName: name,
            bundleIdentifier: "com.test.\(name)",
            appURL: URL(filePath: "/Applications/\(name).app"),
            iconFileName: "\(name).png"
        )
    }

    // MARK: - Index calculation

    @Test func indexAtDockOriginIsZero() {
        #expect(dragTargetIndex(positionX: dockOriginX, count: 5) == 0)
    }

    @Test func indexAtSecondCell() {
        #expect(dragTargetIndex(positionX: dockOriginX + cellSize, count: 5) == 1)
    }

    @Test func indexAtThirdCell() {
        #expect(dragTargetIndex(positionX: dockOriginX + cellSize * 2, count: 5) == 2)
    }

    @Test func indexClampedToZeroWhenBeforeDock() {
        // x=0 is before dockOriginX=10
        #expect(dragTargetIndex(positionX: 0, count: 5) == 0)
    }

    @Test func indexClampedToLastWhenFarRight() {
        #expect(dragTargetIndex(positionX: 10_000, count: 5) == 4)
    }

    @Test func indexClampedToZeroForSingleItem() {
        #expect(dragTargetIndex(positionX: 0,      count: 1) == 0)
        #expect(dragTargetIndex(positionX: 10_000, count: 1) == 0)
    }

    @Test func indexSnapsForwardAfterQuarterCell() {
        // The +cellSize/4 offset means the snap point is 3/4 into the current cell.
        // At exactly 3/4 of the way through cell 0, rawIndex becomes 1.
        let snapPoint = dockOriginX + cellSize * 3 / 4
        #expect(dragTargetIndex(positionX: snapPoint,     count: 5) == 1)
        #expect(dragTargetIndex(positionX: snapPoint - 1, count: 5) == 0)
    }

    // MARK: - Reorder commit

    @Test func commitMoveToFront() {
        let a = makeShortcut(name: "A")
        let b = makeShortcut(name: "B")
        let c = makeShortcut(name: "C")
        // A moved to front: display has nil at original index 0, B and C in place
        let display: [AppShortcut?] = [nil, b, c]
        let result = commitReorder(display: display, targetIndex: 0, dragging: a)
        #expect(result.map(\.displayName) == ["A", "B", "C"])
    }

    @Test func commitMoveToEnd() {
        let a = makeShortcut(name: "A")
        let b = makeShortcut(name: "B")
        let c = makeShortcut(name: "C")
        let display: [AppShortcut?] = [b, c, nil]
        let result = commitReorder(display: display, targetIndex: 2, dragging: a)
        #expect(result.map(\.displayName) == ["B", "C", "A"])
    }

    @Test func commitMoveToMiddle() {
        let a = makeShortcut(name: "A")
        let b = makeShortcut(name: "B")
        let c = makeShortcut(name: "C")
        let d = makeShortcut(name: "D")
        let display: [AppShortcut?] = [b, nil, c, d]
        let result = commitReorder(display: display, targetIndex: 1, dragging: a)
        #expect(result.map(\.displayName) == ["B", "A", "C", "D"])
    }

    @Test func commitPreservesItemCount() {
        let a = makeShortcut(name: "A")
        let b = makeShortcut(name: "B")
        let c = makeShortcut(name: "C")
        let display: [AppShortcut?] = [nil, b, c]
        let result = commitReorder(display: display, targetIndex: 0, dragging: a)
        #expect(result.count == 3)
    }

    @Test func commitWithTwoItemsMoveToEnd() {
        let a = makeShortcut(name: "A")
        let b = makeShortcut(name: "B")
        let display: [AppShortcut?] = [b, nil]
        let result = commitReorder(display: display, targetIndex: 1, dragging: a)
        #expect(result.map(\.displayName) == ["B", "A"])
    }

    @Test func commitWithTwoItemsMoveToFront() {
        let a = makeShortcut(name: "A")
        let b = makeShortcut(name: "B")
        let display: [AppShortcut?] = [nil, b]
        let result = commitReorder(display: display, targetIndex: 0, dragging: a)
        #expect(result.map(\.displayName) == ["A", "B"])
    }

    // MARK: - Cell size contract

    @Test func cellSizeIs64() {
        #expect(DockWidget<EmptyView>.cellSize == 64)
    }

    @Test func widthForCellsScalesLinearly() {
        #expect(DockWidget<EmptyView>.width(for: 1) == 64)
        #expect(DockWidget<EmptyView>.width(for: 3) == 192)
        #expect(DockWidget<EmptyView>.width(for: 0) == 0)
    }
}
