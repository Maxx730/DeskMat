# Plan: Clock Widget Style Setting

## Goal

Add a "Style" dropdown under the clock widget toggle in the Widgets settings tab. Two options to start: **System** (the existing dark glass look) and **Flat** (solid white background, black hands, red second hand). The selected style persists via `@AppStorage` and is applied at runtime without restart.

---

## Existing Pattern

All other style pickers in the app follow this same three-part structure:

1. A `String, CaseIterable` enum in `AppEnums.swift`
2. An `@AppStorage` property bound to a `Picker` in `SettingsView`
3. The widget reads the same `@AppStorage` key and switches its rendering accordingly

---

## Phases

---

### Phase 1 — `ClockStyle` enum + strings

**Scope:** `AppEnums.swift`, `Strings.swift`

**`AppEnums.swift`** — add after the `SystemMetric` enum:

```swift
enum ClockStyle: String, CaseIterable {
    case system = "System"
    case flat   = "Flat"
}
```

**`Strings.swift`** — add a `clockStyle` label inside `Settings`:

```swift
static let clockStyle = "Style"
```

**Result:** The enum and its raw string values are available to the rest of the app.

---

### Phase 2 — Wire `ClockWidget` and `AnalogClockFace` to the style

**Scope:** `ClockWidget.swift`

1. Add `@AppStorage("clockStyle") private var clockStyle: ClockStyle = .system` to `ClockWidget`.

2. Pass `clockStyle` into `AnalogClockFace` as a new `style: ClockStyle` parameter.

3. In `DockWidget(...)` call, set `backgroundColor` based on style:
   ```swift
   DockWidget(backgroundColor: clockStyle == .flat ? .white : nil) {
       AnalogClockFace(date: context.date, style: clockStyle)
   }
   ```
   **System** passes `nil` — `DockWidget` uses its standard dark glass background (the NSPanel material), exactly as it did before any clock style changes were made. **Flat** passes `.white` — the solid white panel introduced in the previous session.

4. In `AnalogClockFace.render(...)`, switch hand and marker colors based on `style`:

   | Element | System (original) | Flat (current) |
   |---|---|---|
   | Canvas background circle | none — dark glass shows through | white filled circle |
   | Hour markers | `white.opacity(0.3)` | `black.opacity(0.25)` |
   | Hour hand | `white.opacity(0.6)`, `dim * 0.01` width | `black`, `dim * 0.02` width |
   | Minute hand | `white.opacity(0.6)`, `dim * 0.01` width | `black`, `dim * 0.02` width |
   | Second hand | `red` | `red` |
   | Center dot outer | `white` | `black` |
   | Center dot inner | `black` | `red` |

   **System** restores the exact values that existed before any visual changes were made to the clock — white semi-transparent hands on the dark panel, no canvas background fill. **Flat** keeps the current state (white panel, black hands, red second hand).

**Result:** Changing `clockStyle` in `@AppStorage` instantly switches both the panel background and the clock face colours.

---

### Phase 3 — Add the Picker to SettingsView

**Scope:** `SettingsView.swift`

1. Add `@AppStorage("clockStyle") private var clockStyle: ClockStyle = .system` to `WidgetsSettingsTab`.

2. After the clock `Toggle` (line 423), add a conditional picker — shown only when the clock is enabled and the user is Pro, matching the pattern used for weather and other widgets:

   ```swift
   if showClockWidget && license.isPro {
       Picker(Strings.Settings.clockStyle, selection: $clockStyle) {
           ForEach(ClockStyle.allCases, id: \.self) { style in
               Text(style.rawValue).tag(style)
           }
       }
   }
   ```

3. Add `ud.set(ClockStyle.system.rawValue, forKey: "clockStyle")` to the `resetToDefaults()` function so reset clears this setting.

**Result:** The settings panel shows a "Style" row below the Clock Widget toggle when Pro and enabled. Selecting System or Flat immediately updates the live clock.

---

## Files Changed

| File | Phase | Change |
|---|---|---|
| `AppEnums.swift` | 1 | Add `ClockStyle` enum |
| `Strings.swift` | 1 | Add `Settings.clockStyle` label |
| `ClockWidget.swift` | 2 | Read `clockStyle`, pass to `DockWidget` + `AnalogClockFace`, branch colors |
| `SettingsView.swift` | 3 | Add `@AppStorage`, Picker, and reset default |
