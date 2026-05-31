import Testing
import AppKit
import SwiftUI
@testable import DeskMat

// MARK: - FirstMouseHostingView.acceptsFirstMouse Tests
//
// FirstMouseHostingView overrides acceptsFirstMouse(for:) to return true so
// that click events are delivered even when the panel is not the key window.
// The superclass (NSHostingView) returns false, which is why the subclass exists.

struct FirstMouseHostingViewTests {

    @Test func acceptsFirstMouseReturnsTrue() {
        let view = FirstMouseHostingView(rootView: EmptyView())
        #expect(view.acceptsFirstMouse(for: nil) == true)
    }

    @Test func superclassReturnsFalse() {
        // NSHostingView.acceptsFirstMouse(for:) returns false — documents why
        // the FirstMouseHostingView subclass was necessary.
        let base = NSHostingView(rootView: EmptyView())
        #expect(base.acceptsFirstMouse(for: nil) == false)
    }

    @Test func acceptsFirstMouseIgnoresEvent() {
        // The override returns true regardless of the event passed in.
        let view = FirstMouseHostingView(rootView: EmptyView())
        #expect(view.acceptsFirstMouse(for: nil) == true)
    }
}
