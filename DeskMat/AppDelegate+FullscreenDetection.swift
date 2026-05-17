import AppKit

// MARK: - Private CGS bridge
// These are undocumented Core Graphics Services symbols used by the system itself
// (Dock, Mission Control) and widely used by window-manager apps. Stable across
// macOS versions. Not App Store safe — gate behind a build flag if that changes.

private typealias CGSConnectionID = UInt32
private typealias CGSSpaceID = UInt64

@_silgen_name("CGSMainConnectionID")
private func CGSMainConnectionID() -> CGSConnectionID

@_silgen_name("CGSGetActiveSpace")
private func CGSGetActiveSpace(_ cid: CGSConnectionID) -> CGSSpaceID

@_silgen_name("CGSSpaceGetType")
private func CGSSpaceGetType(_ cid: CGSConnectionID, _ space: CGSSpaceID) -> Int32

private let kCGSSpaceTypeFullscreen: Int32 = 4

// MARK: - Detection

extension AppDelegate {

    func startFullscreenObserver() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleSpaceChanged),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )

        // Safety poll for any case the Space-change notification doesn't fire.
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 5.0, repeating: 5.0)
        timer.setEventHandler { [weak self] in self?.performFullscreenEval() }
        timer.resume()
        fullscreenPollTimer = timer

        performFullscreenEval()
    }

    func stopFullscreenObserver() {
        fullscreenPollTimer?.cancel()
        fullscreenPollTimer = nil
        NSWorkspace.shared.notificationCenter.removeObserver(
            self,
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
    }

    @objc private func handleSpaceChanged() {
        // Brief delay so CGS has settled on the new Space ID before we query it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.performFullscreenEval()
        }
    }

    private func performFullscreenEval() {
        let fullscreen = isOnFullscreenSpace()
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

    private func isOnFullscreenSpace() -> Bool {
        let cid = CGSMainConnectionID()
        let activeSpace = CGSGetActiveSpace(cid)
        return CGSSpaceGetType(cid, activeSpace) == kCGSSpaceTypeFullscreen
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopFullscreenObserver()
    }
}
