import Testing
import Foundation
@testable import DeskMat

// MARK: - DockWidget Geometry Tests

struct DockWidgetTests {

    @Test func cellSize_is64() {
        #expect(DockWidget<Never>.cellSize == 64)
    }

    @Test func widthForOneCell_is64() {
        #expect(DockWidget<Never>.width(for: 1) == 64)
    }

    @Test func widthForTwoCells_is128() {
        #expect(DockWidget<Never>.width(for: 2) == 128)
    }

    @Test func widthForThreeCells_is192() {
        #expect(DockWidget<Never>.width(for: 3) == 192)
    }

    @Test func widthScalesLinearly() {
        for cells in 1...6 {
            #expect(DockWidget<Never>.width(for: cells) == CGFloat(cells) * 64)
        }
    }
}
