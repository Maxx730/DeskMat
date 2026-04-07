import Testing
import Foundation
@testable import DeskMat

// MARK: - LEDBoardWidget Key Constants
//
// These keys are persisted to UserDefaults and security-scoped bookmarks.
// Changing them silently breaks existing user data on upgrade.

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
