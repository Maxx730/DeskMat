import AppKit
import SwiftUI

@Observable
final class DragGhostState {
    var icon: Image? = nil
    var isShaking: Bool = false
    var showFolderBadge: Bool = false
}

final class DragGhostPanel: NSPanel {

    static let shared = DragGhostPanel()

    private let ghostState = DragGhostState()
    private let panelSize: CGFloat = 90

    private init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 90, height: 90),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 2)
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isMovable = false
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let hostingView = NSHostingView(rootView: DragGhostPanelView(state: ghostState))
        hostingView.autoresizingMask = [.width, .height]
        contentView = hostingView
    }

    // MARK: - Public API

    func show(icon: Image?, at screenPoint: CGPoint) {
        ghostState.icon = icon
        ghostState.isShaking = false
        move(to: screenPoint)
        alphaValue = 1
        orderFront(nil)
    }

    func move(to screenPoint: CGPoint) {
        let origin = NSPoint(
            x: screenPoint.x - panelSize / 2,
            y: screenPoint.y - panelSize / 2
        )
        setFrameOrigin(origin)
    }

    func startShaking() {
        ghostState.isShaking = true
    }

    func setFolderBadge(_ visible: Bool) {
        ghostState.showFolderBadge = visible
    }

    func hide() {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            self.animator().alphaValue = 0
        } completionHandler: {
            self.orderOut(nil)
            self.alphaValue = 1
            self.ghostState.isShaking = false
            self.ghostState.showFolderBadge = false
            self.ghostState.icon = nil
        }
    }
}

private struct DragGhostPanelView: View {
    let state: DragGhostState

    var body: some View {
        DragGhostIcon(icon: state.icon, isShaking: state.isShaking, showFolderBadge: state.showFolderBadge)
            .frame(width: 90, height: 90)
    }
}
