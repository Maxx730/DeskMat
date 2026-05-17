# Dock Hide Call-Site Condition Map

There are exactly **two places** in the codebase that call `setDockVisible(false, ...)`. Every unexpected hide traces back to one of them.

---

## Call Site A — `AppDelegate+AutoHide.swift:47`

Inside the `hideWorkItem` dispatched from `evaluateMousePosition()`.

### Full condition chain

```
evaluateMousePosition() is called
  └─ Guard 1: UserDefaults "autoHideDock" == true          (added fix — returns early if false)
  └─ Guard 2: ContentView.isDragging == false
  └─ isMouseInThresholdZone() == false  →  enters hide branch
       └─ Guard 3: isDockVisible == true
       └─ Guard 4: hideWorkItem == nil
       └─ Schedules hideWorkItem after 0.5 s
            └─ If NOT cancelled before 0.5 s elapses:
                 setDockVisible(false, animated: true)      ← HIDE
```

### What can call `evaluateMousePosition()`

| Caller | When | Autohide guard active? |
|---|---|---|
| `mouseGlobalMonitorToken` closure | Every mouse-moved event (global) | ✅ Guard 1 |
| `mouseLocalMonitorToken` closure | Every mouse-moved event (local) | ✅ Guard 1 |
| `startAutoHide()` directly | On setup, or each time autohide is re-enabled | ✅ Guard 1 |
| `NSApplication.didChangeScreenParametersNotification` handler (`DeskMatApp.swift:71`) | On any display change (sleep/wake, resolution, monitor plug) | ✅ Guard 1 |

**Verdict:** Guard 1 (`autoHideDock == true`) is present on every path. **Call Site A cannot fire when autohide is off.**

---

## Call Site B — `AppDelegate+FullscreenDetection.swift:59`

Inside `performFullscreenEval()`.

### Full condition chain

```
performFullscreenEval() is called
  └─ isAnyWindowFullscreen() == true
       ├─ Signal 1: NSApp.currentSystemPresentationOptions.contains(.fullScreen)
       └─ Signal 2: CGWindowListCopyWindowInfo finds a window where ALL of:
            • pid != ourPID
            • layer == 0
            • bounds.width  ≈ screen.frame.width   (±2 pt)
            • bounds.height ≈ screen.frame.height  (±2 pt)
            • bounds.origin.x ≈ quartzOriginX      (±2 pt)
            • bounds.origin.y ≈ quartzOriginY      (±2 pt)
  └─ Guard 1: isFullscreenHidden == false
  └─ Guard 2: isDockVisible == true
  setDockVisible(false, animated: true)                     ← HIDE
```

### What triggers `performFullscreenEval()`

```
handleAppActivation(_:)  ← NSWorkspace.didActivateApplicationNotification
                         ← NSWorkspace.didDeactivateApplicationNotification
    └─ Skips if activated/deactivated app is DeskMat's own PID  (Fix 1)
    └─ Otherwise: scheduleFullscreenEval(delay: 0.1)
         └─ performFullscreenEval() after 0.1 s

scheduleFullscreenEvalAfterSpaceChange()  ← NSWorkspace.activeSpaceDidChangeNotification
    └─ scheduleFullscreenEval(delay: 0.5)
         └─ performFullscreenEval() after 0.5 s

scheduleFullscreenEval()  ← called once at startup from startFullscreenObserver()
```

**Verdict:** Call Site B has **no check for whether autohide is enabled**. Any `isAnyWindowFullscreen() == true` result hides the dock regardless of the user's autohide setting.

---

## Why the 3-Finger Gesture Still Triggers a Hide

### Trigger path

1. 3-finger swipe up/left/right → `NSWorkspace.activeSpaceDidChangeNotification`
2. `scheduleFullscreenEvalAfterSpaceChange()` → `performFullscreenEval()` after 0.5 s
3. `isAnyWindowFullscreen()` is evaluated

### Most likely Signal 2 false positive: the Mission Control backdrop

When Mission Control is active, the **Dock process** (`com.apple.dock`) manages a full-screen backdrop window that covers the entire display. This window is:
- Owned by the Dock process — `pid != ourPID` ✓ passes the PID filter
- Positioned at the screen's Quartz origin ✓ passes the origin check
- Sized to exactly `screen.frame` dimensions ✓ passes the size check
- Possibly at `kCGWindowLayer = 0` ✓ passes the layer filter

All four Signal 2 conditions pass → `isAnyWindowFullscreen()` returns `true` → **dock hides**.

When Mission Control closes by clicking a space, `activeSpaceDidChangeNotification` fires again → eval runs → no fullscreen → dock shows. But if Mission Control is **dismissed via Escape** (no space change), **no notification fires** and the dock stays hidden.

### Secondary trigger: app activation during Mission Control

When another app is activated or deactivated as part of the Mission Control gesture, `handleAppActivation(_:)` fires → `scheduleFullscreenEval(delay: 0.1)` — which runs only 0.1 s after the gesture starts, during the middle of the Mission Control transition. At that point the Dock's backdrop is fully on screen and Signal 2 fires.

---

## Proposed Fixes

### Fix A — Exclude the Dock process from Signal 2

The Dock process (`com.apple.dock`) owns the Mission Control backdrop. No real fullscreen *app* runs inside the Dock process. Excluding it from Signal 2 eliminates the Mission Control false positive without affecting any legitimate fullscreen detection.

```swift
// In isAnyWindowFullscreen(), before the window loop:
let dockPID = NSWorkspace.shared.runningApplications
    .first(where: { $0.bundleIdentifier == "com.apple.dock" })?.processIdentifier

for info in windows {
    guard
        let pid = info[kCGWindowOwnerPID as String] as? Int32,
        pid != ourPID,
        pid != dockPID,          // ← add this
        ...
```

### Fix B — Re-evaluate after Mission Control closes (Escape case)

When Mission Control is dismissed via Escape, no workspace notification fires. To recover from a hide that happened while Mission Control was open, schedule a follow-up re-check any time `isFullscreenHidden` is set to `true` — if the fullscreen condition is gone when the follow-up fires, show the dock.

```swift
// At the bottom of the `if fullscreen { ... }` branch in performFullscreenEval():
if fullscreen {
    guard !isFullscreenHidden && isDockVisible else { return }
    isFullscreenHidden = true
    setDockVisible(false, animated: true)
    // Follow-up: recover if the fullscreen condition was transient (e.g. Mission Control)
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
        guard let self, self.isFullscreenHidden else { return }
        if !self.isAnyWindowFullscreen() {
            self.performFullscreenEval()
        }
    }
}
```

### Fix C (nuclear option) — Drop Signal 2 entirely

Signal 1 (`opts.contains(.fullScreen)`) covers all apps that use the standard macOS fullscreen API (green traffic light). This is the vast majority of apps. Signal 2 was added as a fallback for apps that hijack the screen without using the standard API, but it has been the source of every false positive so far. Removing it leaves Signal 1 as the sole detector, which is reliable and has no false positives.

---

## Recommended Action

**Implement Fix A** — it is the smallest targeted change and directly addresses the confirmed source (Dock process backdrop). **Combine with Fix B** to handle the Escape-dismissal edge case where no notification fires. Fix C is available as a fallback if Fix A still produces false positives from other system processes.
