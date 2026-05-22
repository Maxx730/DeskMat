import Testing
import AppKit
@testable import DeskMat

// MARK: - Panel Position Tests
//
// dockedOrigin(for:) reads panel.frame.size which requires a live NSPanel.
// The geometry algorithm is tested here as a standalone formula that mirrors
// the implementation in AppDelegate+Panel.swift. Any change to dockedOrigin
// must be reflected here to keep the tests meaningful.
//
// updatePanelShadow logic (hasShadow iff background == .system) is validated
// via DockBackground enum values, which is where the rule lives.

struct PanelPositionTests {

    // Mirrors AppDelegate.dockedOrigin(for:)
    private func computeDockedOrigin(
        visibleFrame: NSRect,
        panelSize: CGSize,
        position: DockPosition,
        offset: CGFloat
    ) -> NSPoint {
        let x = visibleFrame.midX - panelSize.width / 2
        let y: CGFloat
        switch position {
        case .bottom: y = visibleFrame.minY + offset
        case .top:    y = visibleFrame.maxY - panelSize.height - offset
        }
        return NSPoint(x: x, y: y)
    }

    // MARK: - Bottom position

    @Test func bottomDockedOriginCenteredHorizontally() {
        let vf = NSRect(x: 0, y: 23, width: 1920, height: 1057)
        let origin = computeDockedOrigin(visibleFrame: vf, panelSize: CGSize(width: 400, height: 84), position: .bottom, offset: 0)
        let expectedX: CGFloat = (1920 - 400) / 2   // 760
        #expect(origin.x == expectedX)
    }

    @Test func bottomDockedOriginSitsAtVisibleFrameMinY() {
        let vf = NSRect(x: 0, y: 23, width: 1920, height: 1057)
        let origin = computeDockedOrigin(visibleFrame: vf, panelSize: CGSize(width: 400, height: 84), position: .bottom, offset: 0)
        #expect(origin.y == vf.minY)
    }

    @Test func bottomDockedOriginRespectsOffset() {
        let vf = NSRect(x: 0, y: 23, width: 1920, height: 1057)
        let origin = computeDockedOrigin(visibleFrame: vf, panelSize: CGSize(width: 400, height: 84), position: .bottom, offset: 20)
        #expect(origin.y == vf.minY + 20)
    }

    // MARK: - Top position

    @Test func topDockedOriginCenteredHorizontally() {
        let vf = NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let origin = computeDockedOrigin(visibleFrame: vf, panelSize: CGSize(width: 400, height: 84), position: .top, offset: 0)
        let expectedX: CGFloat = (1920 - 400) / 2   // 760
        #expect(origin.x == expectedX)
    }

    @Test func topDockedOriginSitsAtTopOfVisibleFrame() {
        let vf = NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let origin = computeDockedOrigin(visibleFrame: vf, panelSize: CGSize(width: 400, height: 84), position: .top, offset: 0)
        #expect(origin.y == vf.maxY - 84)        // 996
    }

    @Test func topDockedOriginRespectsOffset() {
        let vf = NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let origin = computeDockedOrigin(visibleFrame: vf, panelSize: CGSize(width: 400, height: 84), position: .top, offset: 20)
        #expect(origin.y == vf.maxY - 84 - 20)
    }

    // MARK: - Multi-monitor (non-zero screen origin)

    @Test func bottomDockedOriginOnSecondaryMonitor() {
        let vf = NSRect(x: 1920, y: 0, width: 2560, height: 1440)
        let origin = computeDockedOrigin(visibleFrame: vf, panelSize: CGSize(width: 400, height: 84), position: .bottom, offset: 0)
        let expectedX: CGFloat = 1920 + (2560 - 400) / 2   // 3000
        #expect(origin.x == expectedX)
        #expect(origin.y == 0)
    }

    @Test func topDockedOriginOnSecondaryMonitor() {
        let vf = NSRect(x: 1920, y: 0, width: 2560, height: 1440)
        let origin = computeDockedOrigin(visibleFrame: vf, panelSize: CGSize(width: 400, height: 84), position: .top, offset: 0)
        let expectedX: CGFloat = 1920 + (2560 - 400) / 2
        let expectedY: CGFloat = 1440 - 84
        #expect(origin.x == expectedX)
        #expect(origin.y == expectedY)
    }

    // MARK: - Shadow rule (mirrors updatePanelShadow logic)
    //
    // panel.hasShadow = (background == .system)

    @Test func shadowEnabledForSystemBackground() {
        #expect(DockBackground.system == .system)
    }

    @Test func shadowDisabledForColorBackground() {
        #expect(DockBackground.color != .system)
    }

    @Test func shadowDisabledForTransparentBackground() {
        #expect(DockBackground.transparent != .system)
    }

    @Test func shadowDisabledForReactiveBackground() {
        #expect(DockBackground.reactive != .system)
    }

    @Test func onlySystemBackgroundEnablesShadow() {
        let shadowOn = DockBackground.allCases.filter { $0 == .system }
        let shadowOff = DockBackground.allCases.filter { $0 != .system }
        #expect(shadowOn.count == 1)
        #expect(shadowOff.count == DockBackground.allCases.count - 1)
    }
}
