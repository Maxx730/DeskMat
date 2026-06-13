import Testing
import AppKit
@testable import DeskMat

// MARK: - Multi-Monitor Tests
//
// targetScreen() and NSScreen.displayID cannot easily use mocked NSScreen
// instances (NSScreen is not subclassable). The selection logic is mirrored
// here as a pure function so it can be tested with arbitrary inputs.
// Live NSScreen.main is used where the extension itself is under test.

struct MultiMonitorTests {

    // Mirrors targetScreen() from AppDelegate+Panel.swift
    private func resolveScreen(
        preferredID: Int,
        screens: [NSScreen],
        main: NSScreen?
    ) -> NSScreen? {
        let id = CGDirectDisplayID(preferredID)
        if id != 0, let match = screens.first(where: { $0.displayID == id }) {
            return match
        }
        return main ?? screens.first
    }

    // MARK: - Sentinel value (preferredID == 0 → follow main)

    @Test func sentinelZeroAlwaysFallsBackToMain() {
        guard let main = NSScreen.main else { return }
        let result = resolveScreen(preferredID: 0, screens: NSScreen.screens, main: main)
        #expect(result == main)
    }

    @Test func sentinelZeroWithNoMainUsesFirstScreen() {
        guard let first = NSScreen.screens.first else { return }
        let result = resolveScreen(preferredID: 0, screens: NSScreen.screens, main: nil)
        #expect(result == first)
    }

    @Test func sentinelZeroWithEmptyScreenListReturnsNil() {
        let result = resolveScreen(preferredID: 0, screens: [], main: nil)
        #expect(result == nil)
    }

    // MARK: - Unmatched ID → fall back to main

    @Test func unmatchedPreferredIDFallsBackToMain() {
        guard let main = NSScreen.main else { return }
        // CGDirectDisplayID.max is guaranteed not to match any real display
        let result = resolveScreen(
            preferredID: Int(CGDirectDisplayID.max),
            screens: NSScreen.screens,
            main: main
        )
        #expect(result == main)
    }

    @Test func unmatchedPreferredIDWithNoMainUsesFirstScreen() {
        guard let first = NSScreen.screens.first else { return }
        let result = resolveScreen(
            preferredID: Int(CGDirectDisplayID.max),
            screens: NSScreen.screens,
            main: nil
        )
        #expect(result == first)
    }

    // MARK: - Matched ID → returns correct screen

    @Test func matchedPreferredIDReturnsCorrectScreen() {
        guard let main = NSScreen.main, let id = main.displayID else { return }
        let result = resolveScreen(
            preferredID: Int(id),
            screens: NSScreen.screens,
            main: nil      // main=nil proves result came from match, not fallback
        )
        #expect(result == main)
    }

    @Test func matchedIDTakesPriorityOverMain() {
        // When the preferred ID matches, main is irrelevant
        guard let main = NSScreen.main, let id = main.displayID else { return }
        let sentinel = NSScreen.screens.first { $0 != main } ?? main
        let result = resolveScreen(
            preferredID: Int(id),
            screens: NSScreen.screens,
            main: sentinel  // deliberate mismatch — should be ignored
        )
        #expect(result == main)
    }

    // MARK: - NSScreen.displayID extension

    @Test func mainScreenHasNonNilDisplayID() {
        #expect(NSScreen.main?.displayID != nil)
    }

    @Test func allConnectedScreensHaveDisplayIDs() {
        let missing = NSScreen.screens.filter { $0.displayID == nil }
        #expect(missing.isEmpty)
    }

    @Test func displayIDsAreUnique() {
        let ids = NSScreen.screens.compactMap { $0.displayID }
        #expect(ids.count == Set(ids).count)
    }

    // MARK: - UserDefaults default

    @Test func preferredScreenIDDefaultsToZero() {
        // Zero is the sentinel meaning "follow main display".
        // Confirm the key reads as 0 when unset.
        let saved = UserDefaults.standard.object(forKey: "preferredScreenID")
        defer {
            if let saved { UserDefaults.standard.set(saved, forKey: "preferredScreenID") }
            else { UserDefaults.standard.removeObject(forKey: "preferredScreenID") }
        }
        UserDefaults.standard.removeObject(forKey: "preferredScreenID")
        #expect(UserDefaults.standard.integer(forKey: "preferredScreenID") == 0)
    }

    // MARK: - Threshold zone on secondary screen (non-zero origin)
    //
    // Mirrors isMouseInThresholdZone geometry from AppDelegate+AutoHide.swift.
    // Verifies that x-axis bounds and y thresholds are relative to the screen
    // frame, not the global coordinate origin.

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

    @Test func bottomThresholdZoneOnSecondaryScreen() {
        // Secondary screen placed to the right at x=1920
        let sf = NSRect(x: 1920, y: 0, width: 2560, height: 1440)
        let vf = NSRect(x: 1920, y: 0, width: 2560, height: 1440)
        let panelH: CGFloat = 84
        let dockedMaxY = vf.minY + panelH

        let mouseInside  = NSPoint(x: 3200, y: dockedMaxY + 39) // x inside, y inside threshold
        let mouseOutsideX = NSPoint(x: 100,  y: dockedMaxY)     // x on primary screen
        let mouseAbove   = NSPoint(x: 3200, y: dockedMaxY + 41) // y just beyond threshold

        #expect(inBottomZone(mouse: mouseInside,   sf: sf, visibleFrame: vf, panelHeight: panelH, offset: 0) == true)
        #expect(inBottomZone(mouse: mouseOutsideX, sf: sf, visibleFrame: vf, panelHeight: panelH, offset: 0) == false)
        #expect(inBottomZone(mouse: mouseAbove,    sf: sf, visibleFrame: vf, panelHeight: panelH, offset: 0) == false)
    }

    @Test func topThresholdZoneOnSecondaryScreen() {
        let sf = NSRect(x: 1920, y: 0, width: 2560, height: 1440)
        let vf = NSRect(x: 1920, y: 0, width: 2560, height: 1440)
        let panelH: CGFloat = 84
        let dockedMinY = vf.maxY - panelH

        let mouseInside   = NSPoint(x: 3200, y: dockedMinY - 39)
        let mouseOutsideX = NSPoint(x: 100,  y: dockedMinY)
        let mouseBelow    = NSPoint(x: 3200, y: dockedMinY - 41)

        #expect(inTopZone(mouse: mouseInside,   sf: sf, visibleFrame: vf, panelHeight: panelH, offset: 0) == true)
        #expect(inTopZone(mouse: mouseOutsideX, sf: sf, visibleFrame: vf, panelHeight: panelH, offset: 0) == false)
        #expect(inTopZone(mouse: mouseBelow,    sf: sf, visibleFrame: vf, panelHeight: panelH, offset: 0) == false)
    }
}
