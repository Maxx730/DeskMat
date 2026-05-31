# Plan: Dock Stroke / Border Setting

## Background

The dock panel is borderless and fully SwiftUI-rendered, so a stroke can be
painted as an `.overlay` on top of the existing `.background` block in
`ContentView.swift`. This requires no AppKit changes — `RoundedRectangle` with
`.strokeBorder` sits cleanly above every background mode and respects
`dockCornerRadius` (already stored in `@AppStorage`).

The stroke is opt-in and off by default so existing users see no visual change.
It applies to all four background modes (`.system`, `.color`, `.transparent`,
`.reactive`) since a visible outline is especially useful on `.transparent` where
there is otherwise no dock boundary.

---

## Phases

### Phase 1 — Storage (`ContentView.swift`, `SettingsView.swift`)

Add three new `@AppStorage` keys:

| Key | Type | Default | Reason |
|---|---|---|---|
| `dockStrokeEnabled` | `Bool` | `false` | Off by default — no visual change on upgrade |
| `dockStrokeColorHex` | `String` | `"#FFFFFF80"` | Semi-transparent white works across all background modes |
| `dockStrokeWidth` | `Double` | `1.5` | Subtle 1.5 pt line as the sensible starting point |

Add the same three keys to `resetToDefaults()` in `SettingsView.swift` alongside
the existing background reset lines (~line 134).

No migration needed — missing keys fall back to SwiftUI defaults.

---

### Phase 2 — Render the stroke (`ContentView.swift`)

Add an `.overlay` modifier directly after the existing `.background { … }` block
(~line 162):

```swift
.overlay {
    if dockStrokeEnabled {
        RoundedRectangle(cornerRadius: dockCornerRadius)
            .strokeBorder(
                ColorUtils.fromHex(dockStrokeColorHex),
                lineWidth: dockStrokeWidth
            )
    }
}
```

`strokeBorder` is used instead of `stroke` so the line is inset and never bleeds
outside the dock bounds.

`dockCornerRadius` is already available in `ContentView` and applies correctly for
`.color` and `.reactive` backgrounds. For `.system` and `.transparent` the user
controls the same slider; they can set it to 0 for a sharp rectangle border or
leave it at the default for a rounded outline.

---

### Phase 3 — Settings UI (`SettingsView.swift`)

Add a new `Section("Stroke")` inside `DockSettingsTab`, placed between the
existing `Section(Strings.Settings.background)` and `Section("General")` (icons
section), at roughly line 310:

```
Stroke  [toggle]
  ↳ Color     [color picker]          (shown only when toggle is on)
  ↳ Width  [ 1.5 ] [−][+]            (shown only when toggle is on)
```

- **Toggle**: `Toggle("Stroke", isOn: $dockStrokeEnabled)`
- **Color picker**: `ColorPicker("Color", selection: Binding(...))` — same hex
  round-trip pattern as `dockBackgroundColor`
- **Width**: `Stepper` + `TextField` pair, range `0.5...12`, step `0.5` — same
  pattern as the corner radius control
- The color and width rows use `if dockStrokeEnabled { … }` so they collapse when
  the toggle is off

Add string constants to `Strings.swift`:

```swift
static let stroke      = "Stroke"
static let strokeColor = "Color"
static let strokeWidth = "Width"
```

---

### Phase 4 — Tests (`DeskMatTests/SettingsTests.swift`)

Add to the existing settings test file:

- `dockStrokeEnabledDefaultsToFalse` — key absent → `false`
- `dockStrokeColorHexDefaultsToSemiTransparentWhite` — key absent → `"#FFFFFF80"`
- `dockStrokeWidthDefaultsToOnePointFive` — key absent → `1.5`
- `dockStrokeWidthMinBoundaryRoundTrips` — `0.5` round-trips through UserDefaults
- `dockStrokeWidthMaxBoundaryRoundTrips` — `12.0` round-trips through UserDefaults

---

## Files touched

| File | Change |
|---|---|
| `ContentView.swift` | Add 3× `@AppStorage`; add `.overlay` after `.background` block |
| `SettingsView.swift` | Add `Section("Stroke")` in `DockSettingsTab`; update `resetToDefaults()` |
| `Strings.swift` | Add `stroke`, `strokeColor`, `strokeWidth` constants |
| `DeskMatTests/SettingsTests.swift` | 5 new default/boundary tests |

No other files need to change. `FolderExpansionView` is deliberately excluded —
the folder popup has its own panel background and should not inherit the dock
stroke.

---

## Risks / Notes

- `strokeBorder` on `RoundedRectangle` is fully hardware-composited; no
  performance concern even at high frame rates with reactive backgrounds.
- The stroke renders on top of the reactive shader, which is the correct visual
  order (the edge highlight in the shader already fades — the user's explicit
  stroke sits above it).
- For the `.system` vibrancy mode the stroke corner radius is driven by
  `dockCornerRadius`, which the user already controls. If they want the stroke
  to match the vibrancy material exactly they set the same radius value.
