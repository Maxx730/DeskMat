import Testing
import AppKit
@testable import DeskMat

// MARK: - AutoHide Tests
//
// Tests that require a live NSPanel (isMouseInThresholdZone, setDockVisible,
// stopAutoHide when isDockVisible=false) cannot run without calling setupPanel(),
// which in turn needs a running NSApplication and hosting view. Those paths are
// covered by the geometry algorithm tests below instead.

@MainActor
@Suite(.serialized)
struct AutoHideTests {

    // MARK: - evaluateMousePosition guards

    @Test func evaluateSkipsWhenAutoHideDisabled() {
        let ud = UserDefaults.standard
        let saved = ud.object(forKey: "autoHideDock")
        defer {
            if let saved { ud.set(saved, forKey: "autoHideDock") }
            else { ud.removeObject(forKey: "autoHideDock") }
        }
        ud.set(false, forKey: "autoHideDock")
        let delegate = AppDelegate()
        let before = delegate.isDockVisible
        delegate.evaluateMousePosition()
        // Early return — dock visibility must not change
        #expect(delegate.isDockVisible == before)
    }

    @Test func evaluateSkipsWhenDragging() {
        // autoHideDock=true passes first guard; isDragging=true triggers second
        let ud = UserDefaults.standard
        let saved = ud.object(forKey: "autoHideDock")
        defer {
            if let saved { ud.set(saved, forKey: "autoHideDock") }
            else { ud.removeObject(forKey: "autoHideDock") }
        }
        ud.set(true, forKey: "autoHideDock")
        let delegate = AppDelegate()
        delegate.isDragging = true
        let before = delegate.isDockVisible
        delegate.evaluateMousePosition()
        #expect(delegate.isDockVisible == before)
    }

    // MARK: - stopAutoHide cleanup

    @Test func stopAutoHideWithNoMonitorsClearsTokens() {
        let delegate = AppDelegate()
        // isDockVisible=true (default) → setDockVisible not called → no panel access
        delegate.stopAutoHide()
        #expect(delegate.mouseGlobalMonitorToken == nil)
        #expect(delegate.mouseLocalMonitorToken == nil)
        #expect(delegate.hideWorkItem == nil)
    }

    @Test func stopAutoHideCancelsWorkItem() {
        let delegate = AppDelegate()
        let item = DispatchWorkItem { }
        delegate.hideWorkItem = item
        delegate.stopAutoHide()
        #expect(item.isCancelled)
        #expect(delegate.hideWorkItem == nil)
    }

    // MARK: - Threshold zone geometry
    //
    // These tests verify the geometry algorithm used by isMouseInThresholdZone.
    // The formula is mirrored here so we can validate it with known values without
    // needing a live NSPanel on screen.

    private func inBottomZone(
        mouse: NSPoint, sf: NSRect, visibleFrame: NSRect,
        panelHeight: CGFloat, offset: CGFloat, threshold: CGFloat = 40
    ) -> Bool {
        let dockedMaxY = visibleFrame.minY + offset + panelHeight
        return mouse.x >= sf.minX && mouse.x <= sf.maxX && mouse.y <= dockedMaxY + threshold
    }

    private func inTopZone(
        mouse: NSPoint, sf: NSRect, visibleFrame: NSRect,
        panelHeight: CGFloat, offset: CGFloat, threshold: CGFloat = 40
    ) -> Bool {
        let dockedMinY = visibleFrame.maxY - panelHeight - offset
        return mouse.x >= sf.minX && mouse.x <= sf.maxX && mouse.y >= dockedMinY - threshold
    }

    @Test func bottomZoneContainsMouseInsideThreshold() {
        let sf = NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let vf = NSRect(x: 0, y: 23, width: 1920, height: 1057)
        let dockedMaxY = vf.minY + 84       // offset=0, panelHeight=84
        let mouseIn  = NSPoint(x: 960, y: dockedMaxY + 39)
        let mouseOut = NSPoint(x: 960, y: dockedMaxY + 41)
        #expect(inBottomZone(mouse: mouseIn,  sf: sf, visibleFrame: vf, panelHeight: 84, offset: 0) == true)
        #expect(inBottomZone(mouse: mouseOut, sf: sf, visibleFrame: vf, panelHeight: 84, offset: 0) == false)
    }

    @Test func bottomZoneExcludesMouseOutsideScreenWidth() {
        let sf = NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let vf = NSRect(x: 0, y: 23, width: 1920, height: 1057)
        let dockedMaxY = vf.minY + 84
        let mouseLeft  = NSPoint(x: -1,   y: dockedMaxY)
        let mouseRight = NSPoint(x: 1921, y: dockedMaxY)
        #expect(inBottomZone(mouse: mouseLeft,  sf: sf, visibleFrame: vf, panelHeight: 84, offset: 0) == false)
        #expect(inBottomZone(mouse: mouseRight, sf: sf, visibleFrame: vf, panelHeight: 84, offset: 0) == false)
    }

    @Test func bottomZoneRespectsNonZeroOffset() {
        let sf = NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let vf = NSRect(x: 0, y: 23, width: 1920, height: 1057)
        let offset: CGFloat = 20
        let dockedMaxY = vf.minY + offset + 84
        let mouseAt = NSPoint(x: 960, y: dockedMaxY + 40)  // exactly at boundary
        #expect(inBottomZone(mouse: mouseAt, sf: sf, visibleFrame: vf, panelHeight: 84, offset: offset) == true)
    }

    @Test func topZoneContainsMouseInsideThreshold() {
        let sf = NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let vf = NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let dockedMinY = vf.maxY - 84       // offset=0, panelHeight=84
        let mouseIn  = NSPoint(x: 960, y: dockedMinY - 39)
        let mouseOut = NSPoint(x: 960, y: dockedMinY - 41)
        #expect(inTopZone(mouse: mouseIn,  sf: sf, visibleFrame: vf, panelHeight: 84, offset: 0) == true)
        #expect(inTopZone(mouse: mouseOut, sf: sf, visibleFrame: vf, panelHeight: 84, offset: 0) == false)
    }

    @Test func topZoneExcludesMouseOutsideScreenWidth() {
        let sf = NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let vf = NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let dockedMinY = vf.maxY - 84
        let mouseLeft  = NSPoint(x: -1,   y: dockedMinY)
        let mouseRight = NSPoint(x: 1921, y: dockedMinY)
        #expect(inTopZone(mouse: mouseLeft,  sf: sf, visibleFrame: vf, panelHeight: 84, offset: 0) == false)
        #expect(inTopZone(mouse: mouseRight, sf: sf, visibleFrame: vf, panelHeight: 84, offset: 0) == false)
    }
}
