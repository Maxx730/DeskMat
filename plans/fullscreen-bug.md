# Fullscreen Detection Bug — Diagnosis & Proposed Fixes

## Current Symptom

The dock oscillates between hidden and visible while the user is in a fullscreen terminal: hide → show → hide → show. The previous fix (`fullscreenSourcePID` tracking) addressed the most obvious cause (Xcode debugger activations) but the underlying instability remains.

---

## How We Got Here

Across the last several iterations we have layered **six different guards** onto a fundamentally unreliable signal:

| Layer | What it does | Why it was added |
|---|---|---|
| Workspace notifications | Trigger eval on app activation/deactivation | Initial design |
| `activeSpaceDidChangeNotification` eval | Catch native fullscreen transitions | Hide trigger was missing |
| 2s polling timer | Fire eval regardless of notifications | Some terminals don't fire notifications |
| `.optionAll` window query | See windows on dedicated fullscreen Spaces | `.optionOnScreenOnly` skipped them |
| Frontmost-PID filter | Avoid cross-Space false positives | `.optionAll` sees windows on every Space |
| `fullscreenSourcePID` tracking | Stay hidden when Xcode briefly activates | Frontmost PID flips during transitions |
| 1.5s minimum-hide guard | Suppress immediate flicker | Eval returned `false` mid-transition |
| `!isFullscreenHidden` in `evaluateMousePosition` | Mouse-in-zone wouldn't override fullscreen hide | Mouse path overrode the hide |

Every layer is a patch for a problem caused by an earlier layer. Each one introduces its own edge cases.

---

## Root Cause

We are trying to answer the question **"is an app fullscreen?"** using `CGWindowListCopyWindowInfo` + `NSWorkspace.frontmostApplication`. Neither tool is designed to give a reliable answer to that question from a background process:

1. **`CGWindowListCopyWindowInfo([.optionOnScreenOnly])` silently excludes windows on dedicated fullscreen Spaces.** Confirmed in the logs — Terminal never appeared at `(0, 0, 1470, 956)` until we switched to `.optionAll`.
2. **`.optionAll` returns windows from every Space.** A fullscreen app on Space 2 is indistinguishable from a fullscreen app on the user's current Space. Filtering by frontmost PID is our workaround, but...
3. **`NSWorkspace.frontmostApplication` is volatile.** It changes on every `didActivateApplicationNotification`, which fire during Space transitions, debugger output flushes, notification banners, and any number of background activations.
4. **Window bounds are observable mid-animation.** Even with timing correct, `CGWindowList` will return intermediate sizes during the ~0.5s fullscreen transition, causing spurious false readings.

We are stacking probabilistic guards on top of a signal that is fundamentally not designed for our use case. Every new edge case we encounter requires another guard, and each guard makes the state machine harder to reason about.

---

## Proposed Solutions

### Option A — Continue patching the current approach (NOT recommended)

Add yet another guard: when `fullscreenSourcePID`'s window bounds are mid-animation (neither exactly fullscreen nor exactly windowed), treat as "still fullscreen" and stay hidden. This keeps adding code to an already brittle pipeline. **Estimated complexity: another ~30 lines, plus more edge cases later.**

---

### Option B — Replace the core signal with `NSScreen.visibleFrame` (RECOMMENDED)

**The single most reliable signal for "is the user looking at a fullscreen app right now"** is the difference between `NSScreen.main.frame` and `NSScreen.main.visibleFrame`:

- **Not in fullscreen:** `visibleFrame.maxY < frame.maxY` because the menu bar (~24pt) occupies the top of the screen.
- **In native fullscreen:** `visibleFrame.maxY == frame.maxY` because macOS hides the menu bar.

```swift
private func isOnFullscreenSpace() -> Bool {
    guard let screen = NSScreen.main else { return false }
    return abs(screen.visibleFrame.maxY - screen.frame.maxY) < 1
}
```

**Why this is dramatically better than what we have:**

| Concern | Current approach | `visibleFrame` approach |
|---|---|---|
| Detects native fullscreen on current Space | Sometimes (depends on PID timing) | Always |
| Cross-Space false positives | Needs PID filtering | None — `NSScreen` reflects current Space |
| Notification dependency | Yes (and they don't always fire) | None — pure read |
| Mid-transition flicker | Yes | No — `visibleFrame` flips atomically |
| Lines of code | ~80 across two files | ~5 |
| State variables required | `isFullscreenHidden`, `fullscreenSourcePID`, `lastFullscreenHideDate`, `fullscreenEvalWorkItem`, `fullscreenPollTimer` | `isFullscreenHidden` only |

**Trade-offs:**

- **Loses detection of non-native fullscreen** (e.g., apps that fill the screen via `setFrame:` without going through `toggleFullScreen:`). In practice this is rare and arguably correct — if an app doesn't ask the system to hide the menu bar, the user can see DeskMat just fine.
- **Doesn't work if the user has "Automatically hide and show the menu bar" enabled in System Settings.** The menu bar would always be hidden, so `visibleFrame.maxY == frame.maxY` would always be true. This is a real edge case but a minority setting; can be detected and disabled.
- **Multi-monitor:** We'd need to check the screen DeskMat is currently on, not just `NSScreen.main`. One extra line.

**Trigger model:**

`NSApplication.didChangeScreenParametersNotification` fires whenever the visible frame changes (which includes entering/exiting fullscreen). Combined with a sparse safety poll (e.g., every 3–5 seconds), no more workspace observers, no more space-change observers, no more PID tracking. The dispatch graph collapses to a single method called from two places.

---

### Option C — Use the Accessibility API

Request Accessibility permission, then observe `kAXWindowMovedNotification` and `kAXWindowResizedNotification` on the focused application. This is the most "correct" approach in terms of API design — these notifications are literally what macOS uses internally.

**Cons:** Requires Accessibility permission (user has to grant in System Settings, friction at first run). More complex to implement. Probably overkill for what `visibleFrame` already gives us cleanly.

---

## Recommendation

**Replace the current pipeline with Option B.**

Specifically:

1. Delete `isAnyWindowFullscreen()` and the `CGWindowList` machinery.
2. Delete `fullscreenSourcePID`, `lastFullscreenHideDate`, the 2s poll timer, `scheduleFullscreenEvalAfterSpaceChange`, and `handleAppActivation`.
3. Add `isOnFullscreenSpace()` using `NSScreen.visibleFrame`.
4. Observe `NSApplication.didChangeScreenParametersNotification` to trigger evals.
5. Keep a single, slow safety poll (e.g., every 5s) as belt-and-suspenders.
6. Keep the `!isFullscreenHidden` guard in `evaluateMousePosition`.

This is roughly a **net code reduction of 80–100 lines** and eliminates the entire class of bugs we've been fighting. The only behavior change is for users who have "Automatically hide and show the menu bar" enabled — we can either accept that or add a settings toggle.

---

## Next Step

Get approval on Option B, then implement in one pass. Don't combine with another bandaid on the current pipeline — Option B is meant to replace it entirely.
