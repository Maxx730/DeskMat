import AppKit
import SwiftUI

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}

extension AppDelegate {
    func targetScreen() -> NSScreen {
        let id = CGDirectDisplayID(cachedPreferredScreenID)
        if id != 0, let match = NSScreen.screens.first(where: { $0.displayID == id }) {
            return match
        }
        return NSScreen.main ?? NSScreen.screens[0]
    }

    func setupPanel() {
        let content = ContentView()
            .environment(entitlements)
            .environment(systemMonitor)
            .environment(windowState)
            .environment(dragCoordinator)
            .environment(eveService)
            .environment(mediaRemote)

        let hostingView = FirstMouseHostingView(rootView: content)
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
        NotificationCenter.default.addObserver(self, selector: #selector(dockContentSizeChanged(_:)), name: .dockContentSizeChanged, object: nil)

        updatePanelShadow()
        repositionPanel()
        panel.orderFrontRegardless()

        // Reposition when the setting changes
        positionObserver = UserDefaults.standard.observe(\.dockPosition, options: [.new]) { [weak self] _, change in
            DispatchQueue.main.async {
                if let raw = change.newValue {
                    self?.cachedDockPosition = DockPosition(rawValue: raw) ?? .bottom
                }
                self?.repositionPanel()
            }
        }
        offsetObserver = UserDefaults.standard.observe(\.dockOffset, options: [.new]) { [weak self] _, change in
            DispatchQueue.main.async {
                if let val = change.newValue {
                    self?.cachedDockOffset = CGFloat(val)
                }
                self?.repositionPanel()
            }
        }
        offsetXObserver = UserDefaults.standard.observe(\.dockOffsetX, options: [.new]) { [weak self] _, change in
            DispatchQueue.main.async {
                if let val = change.newValue {
                    self?.cachedDockOffsetX = CGFloat(val)
                }
                self?.repositionPanel()
            }
        }
        preferredScreenIDObserver = UserDefaults.standard.observe(\.preferredScreenID, options: [.new]) { [weak self] _, change in
            DispatchQueue.main.async {
                if let val = change.newValue {
                    self?.cachedPreferredScreenID = val
                }
                self?.repositionPanel()
            }
        }
    }

    func updatePanelShadow() {
        let raw = UserDefaults.standard.string(forKey: "dockBackground") ?? DockBackground.system.rawValue
        let background = DockBackground(rawValue: raw) ?? .system
        panel.hasShadow = background == .system || background == .liquidGlass
    }

    @objc func hostingViewFrameChanged(_ notification: Notification) {
        guard let hostingView = notification.object as? NSView else { return }
        panel.setContentSize(hostingView.fittingSize)
        repositionPanel()
    }

    @objc func dockContentSizeChanged(_ notification: Notification) {
        guard let value = notification.userInfo?["size"] as? NSValue else { return }
        panel.setContentSize(value.sizeValue)
        repositionPanel()
    }

    func dockedOrigin(for screen: NSScreen) -> NSPoint {
        let screenFrame = screen.visibleFrame
        let panelSize = panel.frame.size
        let x = screenFrame.midX - panelSize.width / 2 + cachedDockOffsetX
        let position = cachedDockPosition
        let offset = cachedDockOffset
        let y: CGFloat
        switch position {
        case .bottom: y = screenFrame.minY + offset
        case .top:    y = screenFrame.maxY - panelSize.height - offset
        }
        return NSPoint(x: x, y: y)
    }

    func repositionPanel() {
        panel.setFrameOrigin(dockedOrigin(for: targetScreen()))
    }
}
