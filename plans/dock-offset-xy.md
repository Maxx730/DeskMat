# Plan: Dock X/Y Offset Settings

## Background

The dock currently supports a single `dockOffset: Int` that shifts the panel
vertically (away from the screen edge). The goal is to expose separate X and Y
offsets so the user can also shift the dock horizontally, displayed as a new
"Offsets" section in the Dock tab.

### Current data flow

```
UserDefaults["dockOffset"]
  → UserDefaultsExtensions.dockOffset (KVO @objc dynamic)
  → AppDelegate.offsetObserver (KVO) → cachedDockOffset
  → AppDelegate+Panel.dockedOrigin(for:) → panel Y position only
  → SettingsView DockSettingsTab: single TextField/Stepper row
```

### Approach — keep `dockOffset`, add `dockOffsetX`

Rather than renaming `dockOffset` to `dockOffsetY` (which would silently
reset every existing user's saved offset), the existing key is left in place
and the existing variable is conceptually renamed to "Y" only in the UI.
`dockOffsetX` is a brand-new key defaulting to `0`.

This means no UserDefaults migration is required and no existing tests break.

---

## Phases

### Phase 1 — Storage

**`UserDefaultsExtensions.swift`** — Add a KVO-observable property for X:

```swift
@objc dynamic var dockOffsetX: Int {
    return integer(forKey: "dockOffsetX")
}
```

**`DeskMatApp.swift` (AppDelegate)** — Add cached value and observer slot:

```swift
var cachedDockOffsetX: CGFloat = CGFloat(UserDefaults.standard.integer(forKey: "dockOffsetX"))
var offsetXObserver: Any?
```

**`SettingsView.swift` `resetToDefaults()`** — Add alongside the existing
`dockOffset` reset:

```swift
ud.set(0, forKey: "dockOffsetX")
```

---

### Phase 2 — Panel positioning (`AppDelegate+Panel.swift`)

**`setupPanel()`** — Add a second KVO observer for `dockOffsetX`, mirroring
the existing `offsetObserver` block:

```swift
offsetXObserver = UserDefaults.standard.observe(\.dockOffsetX, options: [.new]) { [weak self] _, change in
    DispatchQueue.main.async {
        if let val = change.newValue { self?.cachedDockOffsetX = CGFloat(val) }
        self?.repositionPanel()
    }
}
```

**`dockedOrigin(for:)`** — Apply the X offset to the centred x calculation:

```swift
let x = screenFrame.midX - panelSize.width / 2 + cachedDockOffsetX
```

The Y logic is unchanged.

---

### Phase 3 — Settings UI (`SettingsView.swift`)

**`DockSettingsTab`** — Add `@AppStorage("dockOffsetX") private var dockOffsetX = 0`.

Remove the existing offset `HStack` row from `Section(Strings.Settings.dock)`.

Add a new `Section(Strings.Settings.offsets)` after the Dock section (before
the Background section) containing two rows — X first, then Y:

```
X  [  0  ] [−][+]
Y  [  0  ] [−][+]
```

Both rows follow the same `HStack { Text / Spacer / TextField / Stepper }`
pattern as the current offset row. No range clamping is needed — positive and
negative values are both valid.

**`Strings.swift`** — Add three constants:

```swift
static let offsets = "Offsets"
static let offsetX = "X"
static let offsetY = "Y"
```

The existing `Settings.offset` constant can be removed since it is no longer
used in the UI. Leave it in place for now to avoid breaking any string-key
search — it can be cleaned up in a future pass.

---

### Phase 4 — Tests

**`DeskMatTests/PanelPositionTests.swift`** (or `AdditionalSettingsTests` if
that file is the right home) — Add:

- `dockOffsetXDefaultsToZero` — key absent → `UserDefaults.integer` returns `0`
- `dockOffsetXPersistedToUserDefaults` — positive and negative values round-trip
- `dockOffsetXKeyIsDistinctFromDockOffsetKey` — `"dockOffsetX" != "dockOffset"`

---

## Files touched

| File | Change |
|---|---|
| `UserDefaultsExtensions.swift` | Add `dockOffsetX` KVO property |
| `DeskMatApp.swift` | Add `cachedDockOffsetX`, `offsetXObserver` |
| `AppDelegate+Panel.swift` | Add X observer; apply X offset in `dockedOrigin(for:)` |
| `SettingsView.swift` | Add `@AppStorage("dockOffsetX")`; move offset row into new `Section("Offsets")` with X + Y rows; update `resetToDefaults()` |
| `Strings.swift` | Add `offsets`, `offsetX`, `offsetY` constants |
| `DeskMatTests/AdditionalSettingsTests` (or `PanelPositionTests.swift`) | 3 new tests for `dockOffsetX` |

---

## Risks / Notes

- Keeping the `dockOffset` key name preserves every existing user's Y offset
  with zero migration code.
- `cachedDockOffsetX` is read on the main thread inside `repositionPanel()`,
  matching the same pattern as `cachedDockOffset` — no threading concern.
- X offset shifts the dock away from center. There is no clamping (unlike
  corner radius and stroke width) — the user may deliberately push the dock
  fully off-screen, which is acceptable.
- The existing `Strings.Settings.offset` constant is intentionally left in
  place to avoid a noisy diff; remove it in a cleanup PR once nothing
  references it.
