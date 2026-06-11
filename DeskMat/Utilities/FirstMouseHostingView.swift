import AppKit
import SwiftUI

/// NSHostingView subclass that accepts the first mouse click even when its
/// window is not key, matching the behaviour of FirstMouseNSButton.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
