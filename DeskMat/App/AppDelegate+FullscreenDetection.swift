import AppKit
import Darwin

// MARK: - Private CGS bridge
// These are undocumented Core Graphics Services symbols used by the system itself
// (Dock, Mission Control) and widely used by window-manager apps. Stable across
// macOS versions. Not App Store safe — gate behind a build flag if that changes.
//
// Loaded via dlsym so that a missing symbol at runtime produces a graceful
// fallback (fullscreen detection disabled) rather than a crash at launch.

private typealias CGSConnectionID = UInt32
private typealias CGSSpaceID = UInt64
private let kCGSSpaceTypeFullscreen: Int32 = 4

private typealias CGSMainConnectionIDFn = @convention(c) () -> CGSConnectionID
private typealias CGSGetActiveSpaceFn   = @convention(c) (CGSConnectionID) -> CGSSpaceID
private typealias CGSSpaceGetTypeFn     = @convention(c) (CGSConnectionID, CGSSpaceID) -> Int32

// RTLD_DEFAULT = ((void*)(intptr_t)-2) on macOS — not importable as a Swift symbol
private let rtldDefault: UnsafeMutableRawPointer? = .init(bitPattern: -2)

private let _cgsMainConnectionID: CGSMainConnectionIDFn? = dlsym(rtldDefault, "CGSMainConnectionID")
    .map { unsafeBitCast($0, to: CGSMainConnectionIDFn.self) }
private let _cgsGetActiveSpace: CGSGetActiveSpaceFn? = dlsym(rtldDefault, "CGSGetActiveSpace")
    .map { unsafeBitCast($0, to: CGSGetActiveSpaceFn.self) }
private let _cgsSpaceGetType: CGSSpaceGetTypeFn? = dlsym(rtldDefault, "CGSSpaceGetType")
    .map { unsafeBitCast($0, to: CGSSpaceGetTypeFn.self) }

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
            setDockVisible(false, animated: true, forceFade: true)
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
        guard let getConn  = _cgsMainConnectionID,
              let getSpace = _cgsGetActiveSpace,
              let getType  = _cgsSpaceGetType else { return false }
        let cid = getConn()
        return getType(cid, getSpace(cid)) == kCGSSpaceTypeFullscreen
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopFullscreenObserver()
    }
}
