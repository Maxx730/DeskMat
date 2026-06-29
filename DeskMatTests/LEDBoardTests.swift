import Testing
import Foundation
@testable import DeskMat

// MARK: - LEDBoardWidget Key Constants
//
// These keys are persisted to UserDefaults and security-scoped bookmarks.
// Changing them silently breaks existing user data on upgrade.

@Suite struct LEDBoardGridFitTests {

    @Test func squareImageFillsSquareGrid() {
        let m = LEDBoardWidget.gridFitMetrics(srcW: 10, srcH: 10, cols: 10, rows: 10)
        #expect(m.scaledW == 10)
        #expect(m.scaledH == 10)
        #expect(m.xOff == 0)
        #expect(m.yOff == 0)
    }

    @Test func wideImageCentersVertically() {
        // 20×10 source → aspect 2:1, wider than 1:1 grid → constrain by width
        let m = LEDBoardWidget.gridFitMetrics(srcW: 20, srcH: 10, cols: 10, rows: 10)
        #expect(m.scaledW == 10)
        #expect(m.scaledH == 5)
        #expect(m.xOff == 0)
        #expect(m.yOff == 2)
    }

    @Test func tallImageCentersHorizontally() {
        // 10×20 source → aspect 1:2, taller than 1:1 grid → constrain by height
        let m = LEDBoardWidget.gridFitMetrics(srcW: 10, srcH: 20, cols: 10, rows: 10)
        #expect(m.scaledW == 5)
        #expect(m.scaledH == 10)
        #expect(m.xOff == 2)
        #expect(m.yOff == 0)
    }

    @Test func gridLargerThanSourceScalesUp() {
        // 2×2 source into 10×10 grid → fills the full grid
        let m = LEDBoardWidget.gridFitMetrics(srcW: 2, srcH: 2, cols: 10, rows: 10)
        #expect(m.scaledW == 10)
        #expect(m.scaledH == 10)
    }

    @Test func minimumGridDimensionIsOne() {
        let m = LEDBoardWidget.gridFitMetrics(srcW: 1, srcH: 1, cols: 1, rows: 1)
        #expect(m.scaledW == 1)
        #expect(m.scaledH == 1)
        #expect(m.xOff == 0)
        #expect(m.yOff == 0)
    }

    @Test func aspectRatioPreserved() {
        // 4×3 source into 12×12 grid → scaledW=12, scaledH=9, ratio preserved
        let m = LEDBoardWidget.gridFitMetrics(srcW: 4, srcH: 3, cols: 12, rows: 12)
        #expect(m.scaledW == 12)
        #expect(m.scaledH == 9)
        let resultRatio = Double(m.scaledW) / Double(m.scaledH)
        let srcRatio = 4.0 / 3.0
        #expect(abs(resultRatio - srcRatio) < 0.01)
    }
}

struct LEDBoardKeyConstantsTests {

    @Test func widthModeKey_isStable() {
        #expect(LEDBoardWidget.widthModeKey == "ledBoardIsWide")
    }

    @Test func bookmarkKey_isStable() {
        #expect(LEDBoardWidget.bookmarkKey == "ledBoardImageBookmark")
    }

    @Test func imagePathKey_isStable() {
        #expect(LEDBoardWidget.imagePathKey == "ledBoardImagePath")
    }

    @Test func scrollSpeedKey_isStable() {
        #expect(LEDBoardWidget.scrollSpeedKey == "ledBoardScrollSpeed")
    }

    @Test func frameSpeedKey_isStable() {
        #expect(LEDBoardWidget.frameSpeedKey == "ledBoardFrameSpeed")
    }

    @Test func allKeysAreDistinct() {
        let keys = [
            LEDBoardWidget.widthModeKey,
            LEDBoardWidget.bookmarkKey,
            LEDBoardWidget.imagePathKey,
            LEDBoardWidget.scrollSpeedKey,
            LEDBoardWidget.frameSpeedKey,
        ]
        #expect(Set(keys).count == keys.count)
    }
}
