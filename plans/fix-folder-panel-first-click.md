# Fix Folder Expansion Panel First-Click

## Diagnosis

`NSHostingView.acceptsFirstMouse(for:)` returns `false` by default.

When the folder panel is not the key window, macOS intercepts the first click to make it key. That click never reaches SwiftUI's gesture recognizer. The user must click twice: once to focus the panel, once to actually fire the tap.

The existing `mouseDown` override on `FolderExpansionPanel` does not help because it only fires when the user clicks the panel's chrome/frame — clicks on the `NSHostingView` content go directly to that view, bypassing the panel's `mouseDown` entirely.

The project already has `FirstMouseNSButton` which solves the identical problem for `NSButton` by overriding `acceptsFirstMouse(for:)`. The fix is the same approach applied to `NSHostingView`.

---

## Solution

### Phase 1 — `FirstMouseHostingView`

Create `DeskMat/FirstMouseHostingView.swift`:

```swift
import AppKit
import SwiftUI

/// NSHostingView subclass that accepts the first mouse click even when its
/// window is not key, matching the behaviour of FirstMouseNSButton.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
```

This is the only code change needed to fix the underlying problem.

---

### Phase 2 — Use `FirstMouseHostingView` in `FolderExpansionPanel`

**`FolderExpansionPanel.swift`**

1. Change the `hostingView` stored property type:
   ```swift
   // before
   private var hostingView: NSHostingView<FolderExpansionView>?
   // after
   private var hostingView: FirstMouseHostingView<FolderExpansionView>?
   ```

2. Change the creation site in `show()`:
   ```swift
   // before
   let hv = NSHostingView(rootView: view)
   // after
   let hv = FirstMouseHostingView(rootView: view)
   ```

3. Remove the now-redundant `mouseDown` override (it was an ineffective attempt at the same fix):
   ```swift
   // delete these lines
   override func mouseDown(with event: NSEvent) {
       super.mouseDown(with: event)
       makeKey()
   }
   ```
   Keep `canBecomeKey: Bool { true }` — it is still needed so the escape key local monitor works.

---

## File Checklist

| File | Change |
|---|---|
| `FirstMouseHostingView.swift` (new) | Generic `NSHostingView` subclass overriding `acceptsFirstMouse` |
| `FolderExpansionPanel.swift` | Swap `NSHostingView` → `FirstMouseHostingView`, remove `mouseDown` override |

---

## Why This Works

`acceptsFirstMouse(for:) → true` tells AppKit: "deliver this mouse-down to me directly, even if my window isn't key." AppKit then:
1. Delivers the event to the view (SwiftUI sees it, gesture fires).
2. Makes the window key as a side effect.

Both happen in one click instead of two.
