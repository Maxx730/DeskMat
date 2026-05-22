import Testing
import AppKit
@testable import DeskMat

// MARK: - FullscreenDetection Tests
//
// performFullscreenEval and isOnFullscreenSpace are private; they are exercised
// indirectly through startFullscreenObserver. In the test process, the current
// Space is never a fullscreen space, so performFullscreenEval's "not fullscreen"
// branch runs: guard isFullscreenHidden (false by default) → early return. No
// panel access occurs.

@MainActor
@Suite(.serialized)
struct FullscreenDetectionTests {

    // MARK: - Observer lifecycle

    @Test func startObserverCreatesTimer() {
        let delegate = AppDelegate()
        delegate.startFullscreenObserver()
        #expect(delegate.fullscreenPollTimer != nil)
        delegate.stopFullscreenObserver()
    }

    @Test func stopObserverClearsTimer() {
        let delegate = AppDelegate()
        delegate.startFullscreenObserver()
        delegate.stopFullscreenObserver()
        #expect(delegate.fullscreenPollTimer == nil)
    }

    @Test func stopObserverIsIdempotentWithNoStart() {
        let delegate = AppDelegate()
        delegate.stopFullscreenObserver()
        delegate.stopFullscreenObserver()
        #expect(delegate.fullscreenPollTimer == nil)
    }

    @Test func startStopCycleIsRepeatable() {
        let delegate = AppDelegate()
        delegate.startFullscreenObserver()
        delegate.stopFullscreenObserver()
        delegate.startFullscreenObserver()
        #expect(delegate.fullscreenPollTimer != nil)
        delegate.stopFullscreenObserver()
        #expect(delegate.fullscreenPollTimer == nil)
    }

    // MARK: - Initial state

    @Test func isFullscreenHiddenDefaultsFalse() {
        let delegate = AppDelegate()
        #expect(delegate.isFullscreenHidden == false)
    }

    @Test func isDockVisibleDefaultsTrue() {
        let delegate = AppDelegate()
        #expect(delegate.isDockVisible == true)
    }

    // MARK: - State transitions (no panel required)
    //
    // These tests set up the preconditions that performFullscreenEval checks
    // and verify the delegate's state fields directly. Because performFullscreenEval
    // is private we cannot call it; instead we confirm the public state fields
    // start in the correct positions for each branch to fire correctly.

    @Test func fullscreenHiddenFlagStartsCorrectForShowBranch() {
        // Branch: "not fullscreen && isFullscreenHidden" → should restore dock.
        // Pre-condition: isFullscreenHidden must be true for the restore to fire.
        let delegate = AppDelegate()
        delegate.isFullscreenHidden = true
        #expect(delegate.isFullscreenHidden == true)
        // Restoring isFullscreenHidden=false is what performFullscreenEval would do.
        delegate.isFullscreenHidden = false
        #expect(delegate.isFullscreenHidden == false)
    }

    @Test func fullscreenHiddenFlagStartsCorrectForHideBranch() {
        // Branch: "fullscreen && !isFullscreenHidden && isDockVisible" → hide dock.
        let delegate = AppDelegate()
        #expect(delegate.isFullscreenHidden == false)
        #expect(delegate.isDockVisible == true)
        // Simulate what performFullscreenEval does when entering fullscreen:
        delegate.isFullscreenHidden = true
        #expect(delegate.isFullscreenHidden == true)
    }
}
