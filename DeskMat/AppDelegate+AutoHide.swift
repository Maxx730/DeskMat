import AppKit

private let peekFraction: CGFloat = 0.18

extension AppDelegate {
    func startAutoHide() {
        guard mouseGlobalMonitorToken == nil else { return }
        mouseGlobalMonitorToken = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            self?.evaluateMousePosition()
        }
        mouseLocalMonitorToken = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            self?.evaluateMousePosition()
            return event
        }
        evaluateMousePosition()
    }

    func stopAutoHide() {
        if let token = mouseGlobalMonitorToken {
            NSEvent.removeMonitor(token)
            mouseGlobalMonitorToken = nil
        }
        if let token = mouseLocalMonitorToken {
            NSEvent.removeMonitor(token)
            mouseLocalMonitorToken = nil
        }
        hideWorkItem?.cancel()
        hideWorkItem = nil
        setDockVisible(true, animated: true)
    }

    func evaluateMousePosition() {
        guard !ContentView.isDragging else { return }
        let mouse = NSEvent.mouseLocation
        let inZone = isMouseInThresholdZone(mouse)
        if inZone {
            hideWorkItem?.cancel()
            hideWorkItem = nil
            if !isDockVisible { setDockVisible(true, animated: true) }
        } else {
            guard isDockVisible, hideWorkItem == nil else { return }
            let work = DispatchWorkItem { [weak self] in
                self?.hideWorkItem = nil
                self?.setDockVisible(false, animated: true)
            }
            hideWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
        }
    }

    func isMouseInThresholdZone(_ mouse: NSPoint) -> Bool {
        guard let screen = panel.screen ?? NSScreen.main else { return true }
        let sf = screen.frame
        let visibleFrame = screen.visibleFrame
        let threshold: CGFloat = 40
        let position = DockPosition(rawValue: UserDefaults.standard.string(forKey: "dockPosition") ?? "Bottom") ?? .bottom
        let offset = CGFloat(UserDefaults.standard.integer(forKey: "dockOffset"))
        let panelHeight = panel.frame.height
        switch position {
        case .bottom:
            let dockedMaxY = visibleFrame.minY + offset + panelHeight
            return mouse.x >= sf.minX && mouse.x <= sf.maxX && mouse.y <= dockedMaxY + threshold
        case .top:
            let dockedMinY = visibleFrame.maxY - panelHeight - offset
            return mouse.x >= sf.minX && mouse.x <= sf.maxX && mouse.y >= dockedMinY - threshold
        }
    }

    func setDockVisible(_ visible: Bool, animated: Bool) {
        isDockVisible = visible
        let animation = HideAnimation(rawValue: UserDefaults.standard.string(forKey: "hideAnimation") ?? "Fade") ?? .fade
        guard animated else {
            panel.alphaValue = visible ? 1.0 : 0.0
            if visible { repositionPanel() }
            return
        }
        switch animation {
        case .fade:
            // If previously slid off-screen, snap back to docked position before fading
            repositionPanel()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                panel.animator().alphaValue = visible ? 1.0 : 0.0
            }
        case .slide:
            // If previously faded out, restore full opacity before sliding
            panel.alphaValue = 1.0
            if visible {
                slideIn()
            } else {
                slideOut()
            }
        }
    }

    private func peekHiddenOrigin(screen: NSScreen, position: DockPosition) -> NSPoint {
        let panelFrame = panel.frame
        let visibleHeight = panelFrame.height * peekFraction
        let hiddenHeight  = panelFrame.height - visibleHeight
        var origin = panelFrame.origin
        switch position {
        case .bottom: origin.y = screen.frame.minY - hiddenHeight
        case .top:    origin.y = screen.frame.maxY - visibleHeight
        }
        return origin
    }

    private func slideOut() {
        guard let screen = panel.screen ?? NSScreen.main else { return }
        let position = DockPosition(rawValue: UserDefaults.standard.string(forKey: "dockPosition") ?? "Bottom") ?? .bottom
        let targetFrame = NSRect(origin: peekHiddenOrigin(screen: screen, position: position),
                                 size: panel.frame.size)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(targetFrame, display: true)
        }
    }

    private func slideIn() {
        guard let screen = panel.screen ?? NSScreen.main else { return }
        let position = DockPosition(rawValue: UserDefaults.standard.string(forKey: "dockPosition") ?? "Bottom") ?? .bottom
        panel.setFrameOrigin(peekHiddenOrigin(screen: screen, position: position))
        let targetFrame = NSRect(origin: dockedOrigin(for: screen), size: panel.frame.size)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(targetFrame, display: true)
        }
    }
}
