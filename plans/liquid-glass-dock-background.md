# DeskMat — Liquid Glass Dock Background

Implement a `DockBackground.liquidGlass` option that replaces the current
`NSVisualEffectView` slab with Apple's Liquid Glass compositor effect applied
to the dock background only. All icons, widgets, and other UI components are
unaffected.

---

## Architecture overview

The entire background system is driven by a single `@AppStorage("dockBackground")`
switch in `ContentView.swift`. Adding Liquid Glass is purely additive — one new
enum case, one new branch in the switch. The panel is already `isOpaque = false` /
`backgroundColor = .clear`, so the compositor preconditions are already met.

---

## Phase 1 — Add the enum case

**File:** `DeskMat/Core/AppEnums.swift`

Add `.liquidGlass` to `DockBackground`:

```swift
enum DockBackground: String, CaseIterable {
    case system      = "System"
    case liquidGlass = "Liquid Glass"
    case color       = "Color"
    case transparent = "Transparent"
    case reactive    = "Reactive"
}
```

---

## Phase 2 — Wire the background switch

**File:** `DeskMat/App/ContentView.swift`

Add a case to the `.background {}` block:

```swift
case .liquidGlass:
    RoundedRectangle(cornerRadius: 20)
        .glassEffect()
```

The shape passed to `.glassEffect()` controls how the system computes
refraction and edge specular. `cornerRadius: 20` matches the general feel
of the existing `.system` material — tune during testing.

---

## Phase 3 — Enable shadow

**File:** `DeskMat/App/AppDelegate+Panel.swift`

`updatePanelShadow()` currently only enables `hasShadow` for `.system`.
Liquid Glass is also a floating surface and needs a shadow:

```swift
func updatePanelShadow() {
    let raw = UserDefaults.standard.string(forKey: "dockBackground") ?? DockBackground.system.rawValue
    let background = DockBackground(rawValue: raw) ?? .system
    panel.hasShadow = background == .system || background == .liquidGlass
}
```

---

## Phase 4 — Settings UI

**File:** `DeskMat/Settings/SettingsView.swift`

No structural change needed. The existing `Picker` iterates `DockBackground.allCases`
and displays `style.rawValue`, so `"Liquid Glass"` appears automatically once
the enum case is added. No sub-options are needed.

---

## File change summary

| File | Change |
|---|---|
| `Core/AppEnums.swift` | Add `.liquidGlass` case to `DockBackground` |
| `App/ContentView.swift` | New case in the background switch |
| `App/AppDelegate+Panel.swift` | `updatePanelShadow()` handles the new case |

---

## Testing checklist

- [ ] Liquid Glass pill renders against the wallpaper with correct blur-behind
- [ ] Icons and widgets are visually unchanged
- [ ] Shadow present (same as `.system`)
- [ ] Dark and light appearance both look correct
- [ ] Switching between background modes at runtime leaves no stale state
