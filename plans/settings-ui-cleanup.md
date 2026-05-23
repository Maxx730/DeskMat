# Settings UI Cleanup — Implementation Plan

Three targeted UI changes to the settings view and background system:

1. Hide the icon visual effects picker from the UI (keep all logic)
2. Add a Pro badge to the reactive style picker; reactive background always accessible
3. Add a `None` case to `ReactiveStyle` as the default — renders transparent, no shader

---

## Phase 1 — Hide icon visual effects picker from UI

**Goal:** Remove the Effects section from `IconsSettingsTab` so users don't see it
yet. All `@AppStorage`, `DockItemShader`, and rendering logic remains untouched.

**File:** `DeskMat/SettingsView.swift` — `IconsSettingsTab`

Remove (or wrap in `if false`) the entire `Section("Effects")` block:

```swift
// DELETE this block:
Section("Effects") {
    Picker(selection: $visualEffect) {
        ForEach(VisualEffect.allCases, id: \.self) { effect in
            Text(effect.rawValue).tag(effect)
        }
    } label: {
        proLabel(Strings.Settings.visualEffect, isPro: license.isPro)
    }
    .disabled(!license.isPro)
    if visualEffect != .none && license.isPro {
        Slider(value: $dockItemShaderIntensity, in: 0.0...1.0) {
            Text(Strings.Settings.effectIntensity)
        }
    }
}
```

Keep all `@AppStorage` declarations (`visualEffect`, `dockItemShaderIntensity`) in
the struct so the values remain readable by `DockItemShader`. Do not touch
`DockItemShader.swift` or `DockItemShaderIntensity`.

If `IconsSettingsTab` becomes empty after removal, also remove the `@Environment`
and unused `@AppStorage` properties to avoid compiler warnings, but leave them in
`DockItemShader.swift` unchanged.

**Acceptance criteria:**
- Effects section no longer appears under the Icons tab.
- Existing `visualEffect` value in `UserDefaults` is preserved and still applied at
  runtime by `DockItemShader`.

---

## Phase 2 — Pro badge on reactive style picker

**Goal:** `DockBackground.reactive` remains selectable by all users. When reactive
is selected, the style picker appears and shows a Pro badge — the picker is
disabled for non-Pro users who stay on the `.none` default (transparent). Pro
users can choose any animated style.

**File:** `DeskMat/SettingsView.swift` — `DockSettingsTab`

**Step 1** — add `@Environment` to `DockSettingsTab`:

```swift
private struct DockSettingsTab: View {
    @Environment(LicenseManager.self) private var license
    // existing @AppStorage properties unchanged
```

**Step 2** — replace the reactive style `Picker` label and add `.disabled`:

```swift
if dockBackground == .reactive {
    Picker(selection: $reactiveStyle) {
        ForEach(ReactiveStyle.allCases, id: \.self) { style in
            Text(style.rawValue).tag(style)
        }
    } label: {
        proLabel(Strings.Settings.reactiveStyle, isPro: license.isPro)
    }
    .disabled(!license.isPro)
}
```

`proLabel` is already defined as a file-scope private function in `SettingsView.swift`.

**Acceptance criteria:**
- `Reactive` option in the background picker works for all users.
- When reactive is selected, the style sub-picker appears with a Pro badge for
  non-Pro users and is disabled (locked on `None`).
- Pro users see no badge and can freely change the style.

---

## Phase 3 — Add `None` case to `ReactiveStyle`

**Goal:** Add `.none = "None"` as the first case in `ReactiveStyle`. It is the
default value. When selected, the reactive background renders transparent —
no shader runs.

### 3a — `AppEnums.swift`

Add `.none` as the **first** case:

```swift
enum ReactiveStyle: String, CaseIterable {
    case none       = "None"
    case lockOn     = "Lock-On"
    case liquidFill = "Liquid Fill"
    case rainbow    = "Rainbow"
    case dvd        = "DVD"
    case eighties   = "80s"
    case voronoi    = "Voronoi"
    case subpixel   = "Subpixel"
    case joker      = "Joker"
}
```

### 3b — `ReactiveBackgroundView.swift`

Add `.none` to `fragmentShaderName` — return any valid shader name as a
placeholder (it will never be called since `ContentView` won't render the
reactive view when style is `.none`):

```swift
case .none: return ""
```

### 3c — `ContentView.swift`

Guard against rendering the reactive view when style is `.none`:

```swift
case .reactive:
    if reactiveStyle != .none {
        ReactiveBackgroundRepresentable(style: reactiveStyle, cornerRadius: dockCornerRadius)
    } else {
        Color.clear
    }
```

### 3d — `SettingsView.swift` — defaults and reset

Change the `@AppStorage` default in `DockSettingsTab`:

```swift
@AppStorage("reactiveStyle") private var reactiveStyle: ReactiveStyle = .none
```

Update the reset function:

```swift
ud.set(ReactiveStyle.none.rawValue, forKey: "reactiveStyle")
```

**Acceptance criteria:**
- `"None"` appears as the first option in the reactive style picker.
- Fresh installs default to `.none` — selecting Reactive background shows a
  transparent dock with no animation.
- All existing animated styles continue to work.
- Non-Pro users are locked on `None` via the disabled picker from Phase 2.

---

## Out of scope

- Exposing `visualEffect` under a different tab or behind a feature flag toggle.
- Gating `DockBackground.reactive` itself on Pro.
- Migrating existing users' stored `reactiveStyle` values (existing raw strings
  are unchanged so any previously chosen style continues to work).
