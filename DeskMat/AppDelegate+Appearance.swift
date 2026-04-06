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
                self?.observeProStatus()
                // A second dispatch waits for SwiftUI's render cycle to complete
                // before measuring fittingSize. The first dispatch runs in the
                // same run loop pass as the observation callback — before SwiftUI
                // has re-rendered ContentView. The second runs on the next pass,
                // by which time fittingSize reflects the updated content (with
                // pro widgets), so the panel resizes correctly.
                DispatchQueue.main.async {
                    guard let self else { return }
                    if let contentView = self.panel.contentView {
                        self.panel.setContentSize(contentView.fittingSize)
                    }
                    self.repositionPanel()
                }
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
