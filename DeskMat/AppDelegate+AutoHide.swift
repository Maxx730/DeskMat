import AppKit

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
        guard entitlements.isPro else {
            if !isDockVisible { setDockVisible(true, animated: true) }
            return
        }
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
        let pf = panel.frame
        let threshold: CGFloat = 40
        let position = entitlements.isPro
            ? DockPosition(rawValue: UserDefaults.standard.string(forKey: "dockPosition") ?? "Bottom") ?? .bottom
            : .bottom
        switch position {
        case .bottom:
            return mouse.x >= sf.minX && mouse.x <= sf.maxX && mouse.y <= pf.maxY + threshold
        case .top:
            return mouse.x >= sf.minX && mouse.x <= sf.maxX && mouse.y >= pf.minY - threshold
        }
    }

    func setDockVisible(_ visible: Bool, animated: Bool) {
        isDockVisible = visible
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                panel.animator().alphaValue = visible ? 1.0 : 0.0
            }
        } else {
            panel.alphaValue = visible ? 1.0 : 0.0
        }
    }
}
