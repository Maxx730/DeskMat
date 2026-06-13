# Multi-Monitor Support Exploration

## Current State

The dock always positions itself on `NSScreen.main` — the screen macOS designates as
primary (the one with the menu bar by default). This is hardcoded in two places:

- `AppDelegate+Panel.swift:97` — `repositionPanel()` calls `NSScreen.main`
- `AppDelegate+AutoHide.swift:55` — `isMouseInThresholdZone()` falls back to `NSScreen.main`

`dockedOrigin(for screen: NSScreen)` already accepts any screen, so the positioning
math is screen-agnostic. The only change needed is which screen gets passed in.

---

## macOS APIs Available

### Enumerating displays

```swift
// All connected screens, ordered (index 0 is not guaranteed to be primary)
NSScreen.screens  // [NSScreen]

// The screen containing the menu bar (user's "main" display)
NSScreen.main     // NSScreen?

// The screen containing the keyboard focus / frontmost window
NSScreen.focused  // deprecated but still works

// Unique persistent ID for each screen — survives arrangement changes
screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
```

### Stable screen identifier

`CGDirectDisplayID` is a `UInt32` that persists across reboots for the same physical
display (as long as it stays connected). It's the right thing to store in UserDefaults
as the user's preferred screen selection.

```swift
extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
    
    // Human-readable name — macOS 10.15+
    var friendlyName: String { localizedName }
}
```

### Detecting screen changes

```swift
NotificationCenter.default.addObserver(
    forName: NSApplication.didChangeScreenParametersNotification,
    object: nil, queue: .main
) { _ in
    // Called when: monitor connected/disconnected, resolution changes,
    // arrangement changes, main screen changes
    repositionPanel()
}
```

This single notification covers every display topology change. On receipt, re-read
`NSScreen.screens`, check if the stored `CGDirectDisplayID` still exists, and
fall back to the main screen if not.

---

## Proposed Implementation

### Storage

Add one new `@AppStorage` key:

```swift
@AppStorage("preferredScreenID") var preferredScreenID: Int = 0
// 0 = "follow main screen" sentinel; otherwise a CGDirectDisplayID
```

`CGDirectDisplayID` is a `UInt32` but `@AppStorage` doesn't support unsigned ints
directly — store as `Int` and cast at use site.

### Screen resolution helper

```swift
// In AppDelegate or a small extension
func targetScreen() -> NSScreen {
    guard preferredScreenID != 0 else { return NSScreen.main ?? NSScreen.screens[0] }
    let id = CGDirectDisplayID(preferredScreenID)
    return NSScreen.screens.first { $0.displayID == id }
        ?? NSScreen.main
        ?? NSScreen.screens[0]
}
```

### Reposition call sites

Replace every `NSScreen.main` with `targetScreen()`:

| File | Line | Change |
|---|---|---|
| `AppDelegate+Panel.swift:97` | `guard let screen = NSScreen.main` | `let screen = targetScreen()` |
| `AppDelegate+AutoHide.swift:55` | `panel.screen ?? NSScreen.main` | `panel.screen ?? targetScreen()` |
| `AppDelegate+AutoHide.swift:112,124` | similar fallbacks | same |

### Settings UI

A `Picker` in the Dock section of Settings:

```swift
Picker("Display", selection: $preferredScreenID) {
    Text("Main Display").tag(0)
    ForEach(NSScreen.screens, id: \.displayID) { screen in
        Text(screen.localizedName).tag(Int(screen.displayID ?? 0))
    }
}
```

The picker needs to refresh when screens change — wrap it in an `onReceive` of
`NSApplication.didChangeScreenParametersNotification`.

### Panel collection behavior

`panel.collectionBehavior` is currently `[.canJoinAllSpaces, .fullScreenAuxiliary]`.
This is fine — the panel will appear on whichever screen it's positioned on regardless
of Space, and it won't fight with full-screen apps on any screen.

No changes needed to the collection behavior.

---

## Edge Cases

| Scenario | Behaviour |
|---|---|
| Preferred screen disconnected | `targetScreen()` falls back to `NSScreen.main`; re-selecting later persists the original ID |
| Only one screen connected | Picker shows one option; feature is inert |
| User changes macOS "main display" assignment in System Settings | `preferredScreenID == 0` follows the new main automatically |
| Screen arrangement changes (swapped positions) | `CGDirectDisplayID` is position-independent; dock stays on the correct physical monitor |
| Mirroring enabled | `NSScreen.screens` returns only one screen when mirroring; treated as single-screen |

---

## Files to Touch

1. `DeskMat/App/DeskMatApp.swift` — add `cachedPreferredScreenID`; register `NSApplication.didChangeScreenParametersNotification` observer
2. `DeskMat/App/AppDelegate+Panel.swift` — replace `NSScreen.main` with `targetScreen()`; add `targetScreen()` helper
3. `DeskMat/App/AppDelegate+AutoHide.swift` — replace `NSScreen.main` fallbacks with `targetScreen()`
4. `DeskMat/Settings/SettingsView.swift` — add Display picker in the Dock section

No new files required. No changes to `AppEnums.swift` or existing position math.

---

## Complexity Estimate

Low. `dockedOrigin(for:)` already accepts any `NSScreen`. The only structural work
is wiring `preferredScreenID` through the call sites and adding the picker. The screen
change notification is the only new reactive logic.
