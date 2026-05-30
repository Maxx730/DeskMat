import AppKit
import SwiftUI

/// Transparent NSButton overlay that overrides acceptsFirstMouse so the very
/// first tap on a non-activating panel fires the action without needing a
/// "focus" click first.
struct FirstMouseClickable: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> NSView {
        let button = FirstMouseNSButton()
        button.bezelStyle = .shadowlessSquare
        button.isBordered = false
        button.isTransparent = true
        button.target = context.coordinator
        button.action = #selector(Coordinator.tapped)
        return button
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    final class Coordinator: NSObject {
        let action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func tapped() { action() }
    }
}

final class FirstMouseNSButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
