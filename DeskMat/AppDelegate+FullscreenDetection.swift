import AppKit

extension AppDelegate {

    func startFullscreenObserver() {
        fullscreenTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.evaluateFullscreenState()
        }

        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(self, selector: #selector(evaluateFullscreenState),
                       name: NSWorkspace.didActivateApplicationNotification, object: nil)
        ws.addObserver(self, selector: #selector(evaluateFullscreenState),
                       name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
    }

    func stopFullscreenObserver() {
        fullscreenTimer?.invalidate()
        fullscreenTimer = nil
        NSWorkspace.shared.notificationCenter.removeObserver(
            self, name: NSWorkspace.didActivateApplicationNotification, object: nil)
        NSWorkspace.shared.notificationCenter.removeObserver(
            self, name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
    }

    @objc func evaluateFullscreenState() {
        let fullscreen = isAnyWindowFullscreen()
        #if DEBUG
        print("[FullscreenDetection] fullscreen=\(fullscreen) isFullscreenHidden=\(isFullscreenHidden) isDockVisible=\(isDockVisible)")
        #endif
        if fullscreen {
            guard !isFullscreenHidden && isDockVisible else { return }
            isFullscreenHidden = true
            setDockVisible(false, animated: true)
        } else {
            guard isFullscreenHidden else { return }
            isFullscreenHidden = false
            let autoHide = UserDefaults.standard.bool(forKey: "autoHideDock")
            if !autoHide || isMouseInThresholdZone(NSEvent.mouseLocation) {
                setDockVisible(true, animated: true)
            }
        }
    }

    private func isAnyWindowFullscreen() -> Bool {
        // --- Signal 1: system presentation options ---
        let opts = NSApp.currentSystemPresentationOptions
        #if DEBUG
        print("[FullscreenDetection] presentationOpts=\(opts)")
        #endif
        if opts.contains(.fullScreen) { return true }
        if opts.contains(.autoHideMenuBar) && opts.contains(.hideDock) { return true }

        // --- Signal 2: window list ---
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return false }

        let ourPID = ProcessInfo.processInfo.processIdentifier
        let screens = NSScreen.screens

        for info in windows {
            guard
                let pid = info[kCGWindowOwnerPID as String] as? Int32,
                pid != ourPID,
                let layer = info[kCGWindowLayer as String] as? Int,
                layer >= 0 && layer < 20,
                let boundsValue = info[kCGWindowBounds as String] as? NSDictionary,
                let bounds = CGRect(dictionaryRepresentation: boundsValue)
            else { continue }

            #if DEBUG
            let name = info[kCGWindowOwnerName as String] as? String ?? "?"
            print("[FullscreenDetection] window '\(name)' pid=\(pid) layer=\(layer) bounds=\(bounds)")
            #endif

            for screen in screens {
                if abs(bounds.width  - screen.frame.width)  < 2,
                   abs(bounds.height - screen.frame.height) < 2 {
                    return true
                }
            }
        }
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopFullscreenObserver()
    }
}
