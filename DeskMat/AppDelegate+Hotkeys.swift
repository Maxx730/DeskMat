import AppKit

extension AppDelegate {
    func setupHotkey() {
        let mask: NSEvent.ModifierFlags = [.command, .shift]
        let keyCode: UInt16 = 2 // 'd' key

        globalHotkeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == mask && event.keyCode == keyCode {
                self?.toggleDock()
            }
        }
        localHotkeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == mask && event.keyCode == keyCode {
                self?.toggleDock()
                return nil
            }
            return event
        }
    }

    @objc func toggleDock() {
        isDockHidden.toggle()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            panel.animator().alphaValue = isDockHidden ? 0 : 1
        }
    }
}
