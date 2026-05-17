# Bug: Dock Hides When Opening Settings or Using Mission Control (Autohide Off)

## Problem Summary

With autohide disabled, two specific actions cause the dock to unexpectedly hide:
1. Opening the DeskMat Settings window
2. Performing a 3-finger slide up (Mission Control)

The autohide system (`AppDelegate+AutoHide.swift`) is not the culprit here — the **fullscreen detection system** (`AppDelegate+FullscreenDetection.swift`) is triggering incorrectly.

---

## Root Cause Analysis

### Root Cause 1 — DeskMat's own window activations trigger fullscreen eval

**File:** `DeskMat/AppDelegate+Windows.swift:157,179`  
**File:** `DeskMat/AppDelegate+FullscreenDetection.swift:6-12`

`openSettings()` calls `NSApp.activate(ignoringOtherApps: true)`, which makes DeskMat the frontmost app and deactivates whatever was previously active. Both fire workspace notifications that `scheduleFullscreenEval()` is registered to handle:

```swift
ws.addObserver(self, selector: #selector(scheduleFullscreenEval),
               name: NSWorkspace.didActivateApplicationNotification, object: nil)
ws.addObserver(self, selector: #selector(scheduleFullscreenEval),
               name: NSWorkspace.didDeactivateApplicationNotification, object: nil)
```

DeskMat opening its own settings window is **not a fullscreen transition**, so triggering a fullscreen eval here is incorrect. This fires `performFullscreenEval()` 0.1s after the settings window appears.

---

### Root Cause 2 — Signal 2 (window list) matches by dimensions only

**File:** `DeskMat/AppDelegate+FullscreenDetection.swift:86-91`

```swift
for screen in screens {
    if abs(bounds.width  - screen.frame.width)  < 2,
       abs(bounds.height - screen.frame.height) < 2 {
        return true
    }
}
```

This check has no position requirement, no layer specificity, and a 2px tolerance. It returns `true` for **any** on-screen window from another process whose width and height happen to match a screen's `frame` dimensions. Common false-positive sources:
- A browser or editor that was manually resized to fill the screen (without entering macOS fullscreen mode)
- Any app using `NSWindow.StyleMask.fullSizeContentView` sized to the full screen
- Any window management tool (Magnet, Moom, Rectangle) that positioned a window at exact screen dimensions

When `performFullscreenEval()` encounters this false positive, it calls `setDockVisible(false, animated: true)` — hiding the dock even though no real fullscreen transition occurred.

---

### Root Cause 3 — `activeSpaceDidChangeNotification` fires during Mission Control

**File:** `DeskMat/AppDelegate+FullscreenDetection.swift:11-12`

```swift
ws.addObserver(self, selector: #selector(scheduleFullscreenEval),
               name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
```

The 3-finger slide up activates Mission Control, which fires `activeSpaceDidChangeNotification`. The 0.1s debounce in `scheduleFullscreenEval()` is too short — Mission Control's window rearrangement animation takes longer to settle. When the eval runs while Mission Control is still transitioning, the window list is in an intermediate state and Signal 2 may find unexpected windows at screen-filling dimensions (e.g., Mission Control's own Dock-owned overlay components that happen to fall in layer 0–19).

---

### Root Cause 4 — Signal 2 window layer filter is too permissive

**File:** `DeskMat/AppDelegate+FullscreenDetection.swift:75-76`

```swift
let layer = info[kCGWindowLayer as String] as? Int,
layer >= 0 && layer < 20,
```

True macOS fullscreen app windows sit at `kCGWindowLayer = 0` (the default normal window layer). The range `[0, 20)` includes floating/utility/toolbar windows from other processes that are not fullscreen at all. Narrowing to `layer == 0` would eliminate a broad class of false positives.

---

## Proposed Fixes

### Fix 1 — Skip fullscreen eval when DeskMat activates its own windows

Replace the raw `scheduleFullscreenEval` selector with a filtering wrapper for the activate/deactivate notifications. Space changes can still use the raw selector since those are always external.

```swift
// AppDelegate+FullscreenDetection.swift — startFullscreenObserver()
ws.addObserver(self, selector: #selector(handleAppActivation(_:)),
               name: NSWorkspace.didActivateApplicationNotification, object: nil)
ws.addObserver(self, selector: #selector(handleAppActivation(_:)),
               name: NSWorkspace.didDeactivateApplicationNotification, object: nil)
```

```swift
@objc func handleAppActivation(_ notification: Notification) {
    if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
       app.processIdentifier == ProcessInfo.processInfo.processIdentifier {
        return  // DeskMat opening/closing its own windows — not a fullscreen event
    }
    scheduleFullscreenEval()
}
```

Also update `stopFullscreenObserver()` to remove observers by `handleAppActivation` selector name instead of `scheduleFullscreenEval`.

---

### Fix 2 — Add Quartz origin check to Signal 2

A true macOS fullscreen window is anchored at the screen's origin. `CGWindowListCopyWindowInfo` returns bounds in Quartz coordinates (y=0 at top of primary screen, y increases downward). The screen's Quartz origin can be computed from `NSScreen.frame` by flipping.

```swift
// In isAnyWindowFullscreen(), replace the inner screen loop:
let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
for screen in screens {
    let quartzOriginX = screen.frame.minX
    let quartzOriginY = primaryHeight - screen.frame.maxY

    if abs(bounds.width  - screen.frame.width)  < 2,
       abs(bounds.height - screen.frame.height) < 2,
       abs(bounds.origin.x - quartzOriginX)     < 2,
       abs(bounds.origin.y - quartzOriginY)     < 2 {
        return true
    }
}
```

This eliminates any window that matches screen dimensions but is not anchored at the screen's top-left corner — which is every non-fullscreen window, including maximized browsers.

---

### Fix 3 — Narrow Signal 2 window layer to `== 0`

Normal app windows (and true fullscreen windows) sit at layer 0. Floating, toolbar, and HUD windows use higher layers. Restricting to layer 0 eliminates those as sources of false positives.

```swift
// Change:
layer >= 0 && layer < 20,
// To:
layer == 0,
```

---

### Fix 4 — Increase debounce for space-change evals

Mission Control's window transition takes ~400ms to complete. Increase the debounce for `activeSpaceDidChangeNotification` so the eval runs after the animation settles. The simplest approach is a longer debounce for space-change events specifically:

```swift
@objc func scheduleFullscreenEval() {
    scheduleFullscreenEvalWithDelay(0.1)
}

@objc func scheduleFullscreenEvalAfterSpaceChange() {
    scheduleFullscreenEvalWithDelay(0.5)
}

private func scheduleFullscreenEvalWithDelay(_ delay: TimeInterval) {
    fullscreenEvalWorkItem?.cancel()
    let work = DispatchWorkItem { [weak self] in self?.performFullscreenEval() }
    fullscreenEvalWorkItem = work
    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
}
```

In `startFullscreenObserver()`, register `scheduleFullscreenEvalAfterSpaceChange` for `activeSpaceDidChangeNotification` instead of `scheduleFullscreenEval`.

---

## Recommended Implementation Order

1. **Fix 1** — Eliminates the Settings-open trigger immediately; zero false-positive risk.
2. **Fix 3** — One-line change; safe narrowing of the layer filter.
3. **Fix 2** — Adds origin check to Signal 2; eliminates the remaining dimension-match false positives.
4. **Fix 4** — Addresses Mission Control edge case; slightly delays the eval for space changes only.

Fixes 1–3 together should fully eliminate both reported triggers.
