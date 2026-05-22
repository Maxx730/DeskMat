# Reactive Background — Settings Sub-Dropdown Plan

Add a secondary picker inside the Background section of Settings that is
only visible when the Reactive background style is selected. Follows the
same conditional-reveal pattern already used for the `.color` case
(ColorPicker + corner radius shown only when Color is selected).

---

## Current state

| Layer | Status |
|---|---|
| Background section | Has one picker for `DockBackground` |
| `.color` sub-options | ColorPicker + corner radius shown conditionally |
| `.reactive` sub-options | Nothing shown yet |
| `ReactiveStyle` enum | Does not exist |

---

## Phase 1 — Define the `ReactiveStyle` enum

**File:** `DeskMat/AppEnums.swift`

Add a new enum for the reactive style options. Initial cases are
placeholders — expand as new modes are built out.

```swift
enum ReactiveStyle: String, CaseIterable {
    case dot    = "Dot"
    case ripple = "Ripple"
    case glow   = "Glow"
}
```

**Acceptance criteria:**
- Enum compiles with at least two cases.
- `CaseIterable` conformance so the picker can use `allCases`.

---

## Phase 2 — Persist the selection

**File:** `DeskMat/UserDefaultsExtensions.swift`

Register a default value for `reactiveStyle` so the app never reads an
undefined state on first launch.

```swift
ud.set(ReactiveStyle.dot.rawValue, forKey: "reactiveStyle")
```

In the settings view struct that owns the Background section, add:

```swift
@AppStorage("reactiveStyle") private var reactiveStyle: ReactiveStyle = .dot
```

**Acceptance criteria:**
- Selection survives app restarts.
- Default is `.dot` on first launch.

---

## Phase 3 — Add the conditional picker to Settings

**File:** `DeskMat/SettingsView.swift`

Mirror the `.color` pattern: show the sub-picker immediately after the
main background picker, guarded by `dockBackground == .reactive`.

```swift
if dockBackground == .reactive {
    Picker(Strings.Settings.reactiveStyle, selection: $reactiveStyle) {
        ForEach(ReactiveStyle.allCases, id: \.self) { style in
            Text(style.rawValue).tag(style)
        }
    }
}
```

A new `Strings.Settings.reactiveStyle` key will also need adding to
`Strings.swift`.

**Acceptance criteria:**
- Sub-picker appears only when Reactive is selected.
- Sub-picker is hidden for all other background styles.
- Selection updates `reactiveStyle` in UserDefaults immediately.

---

## Phase 4 — Pass the selection into `ReactiveBackgroundView`

**File:** `DeskMat/ReactiveBackgroundView.swift`  
**File:** `DeskMat/ContentView.swift`

Update `ReactiveBackgroundRepresentable` to accept a `ReactiveStyle`
binding and forward it to the `NSView` so it can switch behaviour.

```swift
struct ReactiveBackgroundRepresentable: NSViewRepresentable {
    let style: ReactiveStyle

    func makeNSView(context: Context) -> ReactiveBackgroundView {
        ReactiveBackgroundView()
    }

    func updateNSView(_ nsView: ReactiveBackgroundView, context: Context) {
        nsView.reactiveStyle = style
    }
}
```

In `ContentView`:

```swift
case .reactive:
    ReactiveBackgroundRepresentable(style: reactiveStyle)
```

The actual per-style rendering logic is out of scope for this plan —
that belongs in a separate plan per style. For now `reactiveStyle` is
stored on the view and available for future use.

**Acceptance criteria:**
- `ReactiveBackgroundRepresentable` takes a `style` parameter.
- Style changes in Settings propagate to the live view without restart.
- Existing dot/circle rendering is unchanged.

---

## Out of scope

- Implementing the visual behaviour of Ripple, Glow, or any other style.
- Animating the transition between styles.
- Per-style sub-options (color pickers, radius sliders, etc.).
