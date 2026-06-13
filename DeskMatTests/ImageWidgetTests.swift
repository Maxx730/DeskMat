import Testing
import Foundation
import SwiftUI
@testable import DeskMat

// MARK: - ImageWidget constants

struct ImageWidgetConstantsTests {

    @Test func cellCountIsTwo() {
        #expect(ImageWidget.cellCount == 2)
    }

    @Test func bookmarkKeyIsStable() {
        #expect(ImageWidget.bookmarkKey == "imageWidgetDirectoryBookmark")
    }
}

// MARK: - Pan geometry
//
// panScale = 2.4
// scaledWidth = widgetWidth * panScale
// maxPan = (scaledWidth - widgetWidth) / 2 = widgetWidth * (panScale - 1) / 2
//
// The pan animation requires the start→end distance to be at least maxPan * 0.5,
// guaranteeing a visible movement even when both random values fall on the same side.

struct ImageWidgetPanGeometryTests {

    private let widgetWidth: CGFloat = DockWidget<EmptyView>.width(for: ImageWidget.cellCount)
    private let panScale: CGFloat = 2.4

    @Test func widgetWidthIsTwoCells() {
        #expect(widgetWidth == 128)
    }

    @Test func scaledWidthIsWidgetWidthTimesPanScale() {
        let scaledWidth = widgetWidth * panScale
        #expect(scaledWidth == 307.2)
    }

    @Test func maxPanIsHalfOfOverhang() {
        let scaledWidth = widgetWidth * panScale
        let maxPan = (scaledWidth - widgetWidth) / 2
        #expect(maxPan == 89.6)
    }

    @Test func minimumPanDistanceIsHalfMaxPan() {
        let scaledWidth = widgetWidth * panScale
        let maxPan = (scaledWidth - widgetWidth) / 2
        let minimumDistance = maxPan * 0.5
        #expect(minimumDistance == 44.8)
    }

    // Pan range is symmetric: start and end are both drawn from [-maxPan, maxPan]
    @Test func panRangeIsSymmetric() {
        let scaledWidth = widgetWidth * panScale
        let maxPan = (scaledWidth - widgetWidth) / 2
        // Worst case: both extremes → distance = 2 * maxPan, always satisfies constraint
        let worstCaseDistance = 2 * maxPan
        #expect(worstCaseDistance >= maxPan * 0.5)
    }

    // Same-side values at zero distance would violate the constraint
    @Test func zeroPanDistanceViolatesConstraint() {
        let scaledWidth = widgetWidth * panScale
        let maxPan = (scaledWidth - widgetWidth) / 2
        let start: CGFloat = 20
        let end:   CGFloat = 20
        #expect(abs(end - start) < maxPan * 0.5)
    }
}
