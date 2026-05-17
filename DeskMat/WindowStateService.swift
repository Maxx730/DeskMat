import AppKit

/// Centralized window-state tracker. Subscribes to workspace notifications once
/// and does a single CGWindowList query per event, rather than one query per
/// dock button per notification.
@Observable
final class WindowStateService {
    private(set) var windowInfo: [pid_t: (count: Int, hasMinimized: Bool)] = [:]
    private var tokens: [Any] = []

    init() {
        let names: [NSNotification.Name] = [
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didDeactivateApplicationNotification,
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
        ]
        tokens = names.map { name in
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: name, object: nil, queue: .main
            ) { [weak self] _ in self?.refresh() }
        }
        refresh()
    }

    deinit {
        tokens.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
    }

    /// Forces an immediate re-query. Call before branching on window state (e.g. on tap).
    func refresh() {
        guard let raw = CGWindowListCopyWindowInfo(
            [.optionAll, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else {
            windowInfo = [:]
            return
        }

        var updated: [pid_t: (count: Int, hasMinimized: Bool)] = [:]
        for window in raw {
            guard let pid = window[kCGWindowOwnerPID as String] as? pid_t,
                  (window[kCGWindowLayer as String] as? Int) == 0 else { continue }
            let onScreen = (window[kCGWindowIsOnscreen as String] as? Bool) == true
            var entry = updated[pid] ?? (count: 0, hasMinimized: false)
            if onScreen { entry.count += 1 } else { entry.hasMinimized = true }
            updated[pid] = entry
        }
        windowInfo = updated
    }

    /// Returns the window count and minimized state for the given bundle identifier.
    func info(for bundleID: String) -> (count: Int, hasMinimized: Bool) {
        guard let pid = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleID)
            .first?.processIdentifier else { return (0, false) }
        return windowInfo[pid] ?? (0, false)
    }
}
