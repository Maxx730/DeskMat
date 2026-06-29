import AppKit
import SwiftUI

/// NSHostingView subclass that accepts the first mouse click even when its
/// window is not key, matching the behaviour of FirstMouseNSButton.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func layout() {
        super.layout()
        let fitting = fittingSize
        guard fitting.width != frame.size.width else { return }
        NotificationCenter.default.post(
            name: .dockContentSizeChanged,
            object: nil,
            userInfo: ["size": NSValue(size: fitting)]
        )
    }
}
