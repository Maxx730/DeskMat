import AppKit
import Observation

extension AppDelegate {
    func observeProStatus() {
        // withObservationTracking fires onChange exactly once, so we re-register
        // here to keep watching indefinitely. AppDelegate lives for the app's
        // lifetime, so this intentional cycle is safe. If self is ever nil,
        // observation stops silently — acceptable since the app is quitting.
        withObservationTracking {
            _ = entitlements.isPro
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                self?.applyAppearance()
                self?.repositionPanel()
                self?.observeProStatus()
            }
        }
    }

    func applyAppearance() {
        guard entitlements.isPro else {
            NSApp.appearance = nil
            return
        }
        let raw = UserDefaults.standard.string(forKey: "appearanceMode") ?? AppearanceMode.system.rawValue
        let mode = AppearanceMode(rawValue: raw) ?? .system
        switch mode {
        case .system: NSApp.appearance = nil
        case .light:  NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:   NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}
