# Eve Widget Theme

Add a theme setting to the Eve widget that overrides its background color. Defaults to `system` (existing dark glass look). Initial palette: system, red, green, blue — designed to expand later.

---

## Phase 1 — `EveWidgetTheme` model

Create `DeskMat/EveWidgetTheme.swift`:

```swift
enum EveWidgetTheme: String, CaseIterable {
    case system
    case red
    case green
    case blue
}
```

- `RawRepresentable` via `String` raw value makes it directly compatible with `@AppStorage`.
- Add a computed property for the resolved color to pass to `DockWidget`:

```swift
extension EveWidgetTheme {
    var color: Color? {
        switch self {
        case .system: return nil   // DockWidget uses its default dark glass
        case .red:    return Color(red: 0.55, green: 0.08, blue: 0.08, opacity: 0.85)
        case .green:  return Color(red: 0.08, green: 0.40, blue: 0.15, opacity: 0.85)
        case .blue:   return Color(red: 0.08, green: 0.18, blue: 0.55, opacity: 0.85)
        }
    }

    var displayName: String {
        switch self {
        case .system: return "System"
        case .red:    return "Red"
        case .green:  return "Green"
        case .blue:   return "Blue"
        }
    }
}
```

Colors are dark, semi-transparent tints so white text remains readable over any desktop.

Add strings to `Strings.Eve`:

```swift
static let themeLabel = "Theme"
```

---

## Phase 2 — Wire into `EveWidget`

In `EveWidget.swift`:

1. Add `@AppStorage("eveWidgetTheme") private var theme: EveWidgetTheme = .system`
2. Pass `backgroundColor: theme.color` to `DockWidget(...)`:

```swift
DockWidget(
    cells: 2,
    isLoading: eveService.isLoading,
    backgroundColor: theme.color,
    onRefresh: { await eveService.refresh() }
) { ... }
```

`DockWidget` already accepts `backgroundColor: Color?` and renders it correctly — no changes needed there.

---

## Phase 3 — Settings UI

In `WidgetsSettingsTab` (inside the `if showEveWidget && license.isPro` block), add a `Picker` below the connect/disconnect UI:

```swift
@AppStorage("eveWidgetTheme") private var eveWidgetTheme: EveWidgetTheme = .system

// inside the Eve section:
Picker(Strings.Eve.themeLabel, selection: $eveWidgetTheme) {
    ForEach(EveWidgetTheme.allCases, id: \.self) { theme in
        Text(theme.displayName).tag(theme)
    }
}
.pickerStyle(.segmented)
```

- Picker only visible when the widget is enabled and the user is authenticated (same guard as the disconnect button).
- Uses `.segmented` style to match other small option groups in the settings (e.g., temperature unit, clock style).
- `@AppStorage` binding means the widget reacts instantly — no save button needed.

---

## Notes

- The `eveWidgetTheme` key lives entirely in `UserDefaults` via `@AppStorage` — no migration needed.
- Future themes (e.g., Eve Corporation colors, gradient, gold) are additive: add a case to the enum and a color to the switch.
- If a gradient or image theme is ever needed, `backgroundColor: Color?` on `DockWidget` can be extended to a `BackgroundStyle` at that point.
