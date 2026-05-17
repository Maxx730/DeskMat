# Bug: Dock Still Hides After Autohide Is Disabled

## Problem Summary

When the user turns autohide ON, the dock hides/shows based on mouse position as expected. When the user turns autohide OFF, the dock can still hide unexpectedly. This document identifies the root causes and proposes fixes.

---

## Root Cause Analysis

### Bug 1 (Primary) — `evaluateMousePosition()` has no autohide guard

**File:** `DeskMat/AppDelegate+AutoHide.swift`  
**File:** `DeskMat/DeskMatApp.swift:70-73`

```swift
// DeskMatApp.swift — fires regardless of autohide state
NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
    object: nil, queue: .main) { [weak self] _ in
    self?.evaluateMousePosition()   // <-- no autohide check
}
```

`evaluateMousePosition()` itself also has no check for whether autohide is enabled:

```swift
func evaluateMousePosition() {
    guard !ContentView.isDragging else { return }
    // No guard for autoHide being enabled!
    let inZone = isMouseInThresholdZone(NSEvent.mouseLocation)
    // ... schedules hide work item if mouse is outside zone
}
```

**Consequence:** Any time screen parameters change (display wakes, external monitor connects/disconnects, resolution changes) with autohide OFF, `evaluateMousePosition()` fires. If the mouse is outside the threshold zone and `isDockVisible == true` and `hideWorkItem == nil` (the correct state when autohide is off), a hide `DispatchWorkItem` is scheduled. 0.5 seconds later the dock hides.

---

### Bug 2 (Contributing) — `stopAutoHide()` unconditionally calls `setDockVisible(true, animated: true)`

**File:** `DeskMat/AppDelegate+AutoHide.swift:18-30`  
**File:** `DeskMat/DeskMatApp.swift:60-68`

The `UserDefaults.didChangeNotification` observer fires for **any** UserDefaults change — not just `autoHideDock`. When autohide is OFF, every time any setting changes (position, offset, theme, etc.), the handler runs and calls `stopAutoHide()`, which always calls `setDockVisible(true, animated: true)`.

For the **slide animation**, `setDockVisible(true, ...)` calls `slideIn()`:

```swift
private func slideIn() {
    ...
    panel.setFrameOrigin(peekHiddenOrigin(screen: screen, position: position)) // SNAP off-screen
    let targetFrame = NSRect(origin: dockedOrigin(for: screen), size: panel.frame.size)
    NSAnimationContext.runAnimationGroup { ... // then animate back }
}
```

`slideIn()` **always snaps the panel to the near-hidden peek position before animating back**, even when the panel is already at the docked position. With autohide OFF, calling this repeatedly causes the dock to snap off-screen and slide back in on every UserDefaults write — making it appear to continuously hide.

---

### Bug 3 (Edge case) — Animation conflict when toggling autohide mid-slide

**File:** `DeskMat/AppDelegate+AutoHide.swift`

If the dock is mid-way through a `slideOut()` animation when the user turns off autohide, `stopAutoHide()` calls `setDockVisible(true, animated: true)` → `slideIn()`. `slideIn()` starts by calling `panel.setFrameOrigin(peekHiddenOrigin(...))` to snap the panel, but the still-running `NSAnimationContext` from `slideOut()` may fight this by animating the frame to the fully-hidden position, leaving the dock in an indeterminate state.

---

## Proposed Fixes

### Fix 1 — Guard `evaluateMousePosition()` against disabled autohide

Add a single guard at the top of `evaluateMousePosition()` so it is a no-op when autohide is off, regardless of what calls it.

```swift
// AppDelegate+AutoHide.swift
func evaluateMousePosition() {
    guard UserDefaults.standard.bool(forKey: "autoHideDock") else { return }
    guard !ContentView.isDragging else { return }
    // ... rest unchanged
}
```

This is the smallest, safest fix. It protects against both Bug 1 (screen parameter notifications) and any future callers.

---

### Fix 2 — Guard `stopAutoHide()` so it only shows the dock when hidden

Avoid calling `setDockVisible(true, ...)` when the dock is already visible. This eliminates the erroneous `slideIn()` snap when autohide is disabled.

```swift
// AppDelegate+AutoHide.swift
func stopAutoHide() {
    if let token = mouseGlobalMonitorToken {
        NSEvent.removeMonitor(token)
        mouseGlobalMonitorToken = nil
    }
    if let token = mouseLocalMonitorToken {
        NSEvent.removeMonitor(token)
        mouseLocalMonitorToken = nil
    }
    hideWorkItem?.cancel()
    hideWorkItem = nil
    if !isDockVisible {                        // only restore if actually hidden
        setDockVisible(true, animated: true)
    }
}
```

---

### Fix 3 — Make the `UserDefaults.didChangeNotification` observer target only `autoHideDock`

Replace the broad notification with a targeted KVO observer that only fires when `autoHideDock` actually changes value.

```swift
// DeskMatApp.swift — in applicationDidFinishLaunching, replace the broad observer:
autoHideObserver = UserDefaults.standard.observe(\.autoHideDock, options: [.new]) { [weak self] _, change in
    DispatchQueue.main.async {
        guard let self else { return }
        if change.newValue == true {
            self.startAutoHide()
        } else {
            self.stopAutoHide()
        }
    }
}
```

This requires adding a `UserDefaults` extension for the `autoHideDock` key (similar to the existing `dockPosition` and `dockOffset` extensions in `UserDefaultsExtensions.swift`) and storing the observer token in a property on `AppDelegate`.

---

### Fix 4 — Prevent `slideIn()` from snapping when already at docked position

Add a position check inside `slideIn()` so it only performs the snap-then-animate sequence when the panel is actually off-screen.

```swift
// AppDelegate+AutoHide.swift
private func slideIn() {
    guard let screen = panel.screen ?? NSScreen.main else { return }
    let position = cachedDockPosition
    let docked = dockedOrigin(for: screen)
    // Only snap if the panel is not already at the docked position
    if panel.frame.origin != docked {
        panel.setFrameOrigin(peekHiddenOrigin(screen: screen, position: position))
    }
    let targetFrame = NSRect(origin: docked, size: panel.frame.size)
    NSAnimationContext.runAnimationGroup { ctx in
        ctx.duration = 0.25
        ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
        panel.animator().setFrame(targetFrame, display: true)
    }
}
```

---

## Recommended Implementation Order

1. **Fix 1** — Highest priority; single-line guard eliminates the primary hide-when-disabled bug.
2. **Fix 2** — Low risk; prevents the unnecessary `slideIn()` snap on every `stopAutoHide()` call.
3. **Fix 4** — Defensive improvement to `slideIn()` to prevent visual artifacts.
4. **Fix 3** — Refactor to use targeted KVO instead of the broad notification; reduces unnecessary calls and is more semantically correct. Requires a small `UserDefaultsExtensions.swift` addition.

Fixes 1 and 2 together should fully resolve the reported bug with minimal code change.
