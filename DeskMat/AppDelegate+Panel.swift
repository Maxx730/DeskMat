import AppKit
import SwiftUI

extension AppDelegate {
    func setupPanel() {
        let content = ContentView()

        let hostingView = NSHostingView(rootView: content)
        hostingView.setFrameSize(hostingView.fittingSize)

        panel = DeskMatPanel(
            contentRect: NSRect(x: 0, y: 0, width: hostingView.fittingSize.width, height: hostingView.fittingSize.height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.contentView = hostingView
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = false
        panel.isMovable = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.acceptsMouseMovedEvents = true

        // Resize panel when SwiftUI content changes size
        hostingView.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(hostingViewFrameChanged(_:)), name: NSView.frameDidChangeNotification, object: hostingView)

        repositionPanel()
        panel.orderFrontRegardless()

        // Reposition when the setting changes
        positionObserver = UserDefaults.standard.observe(\.dockPosition, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.repositionPanel() }
        }
        offsetObserver = UserDefaults.standard.observe(\.dockOffset, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.repositionPanel() }
        }
    }

    @objc func hostingViewFrameChanged(_ notification: Notification) {
        guard let hostingView = notification.object as? NSView else { return }
        panel.setContentSize(hostingView.fittingSize)
        repositionPanel()
    }

    func repositionPanel() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let panelSize = panel.frame.size
        let x = screenFrame.midX - panelSize.width / 2
        let position = DockPosition(rawValue: UserDefaults.standard.string(forKey: "dockPosition") ?? "Bottom") ?? .bottom
        let offset = CGFloat(UserDefaults.standard.integer(forKey: "dockOffset"))
        let y: CGFloat
        switch position {
        case .bottom: y = screenFrame.minY + offset
        case .top:    y = screenFrame.maxY - panelSize.height - offset
        }
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
