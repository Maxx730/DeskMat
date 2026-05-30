import AppKit
import Observation
import SwiftUI

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
                self?.observeProStatus()
                // Panel resize and reposition are handled automatically by the
                // hostingViewFrameChanged observer in AppDelegate+Panel.swift,
                // which fires once SwiftUI has re-rendered and the hosting view
                // frame settles to its new fittingSize.
            }
        }
    }

    func applyAppearance() {
        let raw = UserDefaults.standard.string(forKey: "appearanceMode") ?? AppearanceMode.system.rawValue
        let mode = AppearanceMode(rawValue: raw) ?? .system
        switch mode {
        case .system: NSApp.appearance = nil
        case .light:  NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:   NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}
