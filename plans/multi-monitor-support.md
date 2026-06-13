# DeskMat — Multi-Monitor Support Plan

Allow the user to choose which connected display the dock appears on.
The dock repositions when monitors are connected or disconnected and
falls back to the main display if the preferred one goes away.

Reference: `explorations/multi-monitor-support.md`

---

## File layout

No new files. Four existing files change:

| File | Change |
|---|---|
| `App/DeskMatApp.swift` | `cachedPreferredScreenID`; screen-change notification observer |
| `App/AppDelegate+Panel.swift` | `targetScreen()` helper; replace `NSScreen.main` calls |
| `App/AppDelegate+AutoHide.swift` | replace `NSScreen.main` fallbacks with `targetScreen()` |
| `Settings/SettingsView.swift` | Display picker in the Dock section |

---

## Phase 1 — Core screen targeting

Goal: introduce `targetScreen()` and wire it to all existing positioning code.
No UI yet — the dock silently targets `NSScreen.main` exactly as before, but
now through a single replaceable helper.

### 1a — `DeskMatApp.swift`: add `cachedPreferredScreenID`

```swift
var cachedPreferredScreenID: Int {
    UserDefaults.standard.integer(forKey: "preferredScreenID")
    // 0 = sentinel meaning "follow main display"
}
```

Register the screen-change observer here alongside the existing UserDefaults
observers. On receipt, call `repositionPanel()`.

```swift
NotificationCenter.default.addObserver(
    forName: NSApplication.didChangeScreenParametersNotification,
    object: nil,
    queue: .main
) { [weak self] _ in
    self?.repositionPanel()
}
```

### 1b — `AppDelegate+Panel.swift`: add `targetScreen()` and replace `NSScreen.main`

```swift
func targetScreen() -> NSScreen {
    let id = CGDirectDisplayID(cachedPreferredScreenID)
    if id != 0, let match = NSScreen.screens.first(where: { $0.displayID == id }) {
        return match
    }
    return NSScreen.main ?? NSScreen.screens[0]
}
```

Add the `displayID` helper on `NSScreen`:

```swift
extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
```

Replace in `repositionPanel()`:

```swift
// Before
guard let screen = NSScreen.main else { return }
// After
let screen = targetScreen()
```

### 1c — `AppDelegate+AutoHide.swift`: replace `NSScreen.main` fallbacks

```swift
// Before
guard let screen = panel.screen ?? NSScreen.main else { return true }
// After
let screen = panel.screen ?? targetScreen()
```

Apply the same substitution to all other `NSScreen.main` references in this file
(lines ~112, ~124).

**Verification:** With two monitors connected, temporarily hardcode
`cachedPreferredScreenID` to the secondary display's ID and confirm the dock
appears on that screen and auto-hide still works.

---

## Phase 2 — Settings UI: display picker

Goal: expose a Picker in Settings so the user can choose their preferred display.
The picker rebuilds when monitors are connected or disconnected.

### 2a — `Strings.swift`: add keys

```swift
enum Settings {
    // existing...
    static let display             = "Display"
    static let displayMainFollows  = "Main Display"
}
```

### 2b — `SettingsView.swift`: add picker to the Dock section

```swift
@AppStorage("preferredScreenID") private var preferredScreenID: Int = 0
@State private var screens: [NSScreen] = NSScreen.screens

Picker(Strings.Settings.display, selection: $preferredScreenID) {
    Text(Strings.Settings.displayMainFollows).tag(0)
    ForEach(screens, id: \.displayID) { screen in
        Text(screen.localizedName).tag(Int(screen.displayID ?? 0))
    }
}
.onReceive(
    NotificationCenter.default.publisher(
        for: NSApplication.didChangeScreenParametersNotification)
) { _ in
    screens = NSScreen.screens
    // If the stored screen is no longer present, reset to "main"
    if preferredScreenID != 0,
       !screens.contains(where: { Int($0.displayID ?? 0) == preferredScreenID }) {
        preferredScreenID = 0
    }
}
```

Place the picker immediately below the Position (top/bottom) picker in the
Dock section so the two display-related settings are grouped together.

**Verification:** With two monitors connected the picker should list both by
name. Selecting the secondary display should move the dock immediately. Closing
the secondary display should reset the picker to "Main Display" automatically.

---

## Phase 3 — Polish and edge cases

Goal: handle the remaining edge cases and tidy up.

### 3a — Disconnect fallback

When `didChangeScreenParametersNotification` fires and the preferred screen is
gone, `targetScreen()` already falls back to `NSScreen.main`. Confirm that
`repositionPanel()` is called at that point so the dock actually moves, not
just the stored ID.

### 3b — Single-display hiding

When only one screen is connected, hide the Display picker entirely (it offers
no real choice and adds noise):

```swift
if screens.count > 1 {
    // show picker
}
```

### 3c — Auto-hide threshold on secondary screen

Verify `isMouseInThresholdZone()` correctly uses the secondary screen's frame
when the dock is on that screen. The `panel.screen` property returns the screen
the panel is currently on, so `panel.screen ?? targetScreen()` should be correct
automatically — just needs manual testing.
