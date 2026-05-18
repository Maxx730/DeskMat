# Plan: Dock Corner Radius Setting

## Background

The dock panel is borderless (`styleMask: [.borderless, .nonactivatingPanel]`) with
`backgroundColor = .clear`, so every pixel of the dock's visual shape is owned by
SwiftUI — not by macOS window chrome. Corner radius is fully controllable without
private APIs.

Corner radius only applies to the **solid color** background mode. The other modes
are excluded by design:
- `.system` (vibrancy) — macOS draws the vibrancy material; its shape is managed by
  the window server. The shadow is already enabled for this mode and should stay as-is.
- `.transparent` — no visible surface to round.

Shadow behavior is already correct: `updatePanelShadow()` in `AppDelegate+Panel.swift`
sets `panel.hasShadow = background == .system`, so the shadow is already off for
`.color` and `.transparent`. No change needed there.

Current state of `.color` case in `ContentView.swift`:
```swift
case .color:
    RoundedRectangle(cornerRadius: 16)   // hardcoded — to be parameterized
        .fill(ColorUtils.fromHex(dockBackgroundColorHex))
```

---

## Phases

### Phase 1 — Storage

- Add `@AppStorage("dockCornerRadius") var dockCornerRadius: Double = 16` to `ContentView`
- Default of `16` matches the current hardcoded value so existing users see no change on upgrade
- No UserDefaults migration needed (missing key → SwiftUI default → `16`)

---

### Phase 2 — Apply radius in ContentView.swift

Only the `.color` case changes:

```swift
case .color:
    RoundedRectangle(cornerRadius: dockCornerRadius)
        .fill(ColorUtils.fromHex(dockBackgroundColorHex))
```

`.system` and `.transparent` are untouched.

---

### Phase 3 — Settings UI (SettingsView.swift)

Location: Appearance tab, nested inside / below the Dock Background color picker — only
visible when `.color` is the selected background mode.

Control: A labeled `Stepper` + `TextField` pair (same pattern used for Dock Offset):

```
Corner Radius   [  16  ] [−][+]
```

- Range: `0...64` (0 = square, 64 = pill-shaped at typical dock heights)
- Step: `1`
- The control is hidden entirely when background is `.system` or `.transparent`
- Value updates are instant via `@AppStorage` — no explicit apply step needed

String constant to add to `Strings.swift`:
```swift
static let cornerRadius = "Corner Radius"
```

---

### Phase 4 — Tests

- Add to `SettingsTests.swift`:
  - `dockCornerRadius` defaults to `16` when the key is absent
  - Boundary values `0` and `64` round-trip through `UserDefaults` correctly

---

## Files touched

| File | Change |
|---|---|
| `ContentView.swift` | Add `@AppStorage`, parameterize `.color` case only |
| `SettingsView.swift` | Add Stepper+TextField, shown only when background is `.color` |
| `Strings.swift` | Add `cornerRadius` string constant |
| `DeskMatTests/SettingsTests.swift` | Default-value and boundary tests |

`VisualEffectBackground` is **not** touched — the vibrancy background is out of scope.
`AppDelegate+Panel.swift` is **not** touched — shadow logic is already correct.

---

## Risks / Notes

- No migration needed. The existing hardcoded `16` becomes the default, so the dock
  looks identical to today when the user has never changed the setting.
- Corner radius only has a visible effect with the `.color` background, so hiding the
  control for other modes avoids user confusion without restricting functionality.
