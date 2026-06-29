# DeskMat — Per-Icon Background Color Override

Allow users to override the auto-derived background color of a dock icon with a
custom color. The override is stored per `AppShortcut`, exposed via a color
picker in the add/edit sheet, and falls back to the existing average-color
behaviour when not set.

---

## How the background color works today

`AppShortcutButton.loadIcon()` computes `avgColor` from the icon image via
`ColorUtils.averageColor(of:)`. This drives:

- The rounded-rect background fill (`RoundedRectangle.fill(avgColor)`)
- The window-indicator dot (`Capsule.fill(avgColor…)`)
- The frontmost-app border (`brightenedHSV(avgColor)`)

The override only applies when the global `showIconBackground` setting is `true`
(background-mode). When the setting is `false`, the full-bleed icon is shown and
no background colour is involved.

---

## Phase 1 — Model: add `backgroundColorHex` to `AppShortcut`

**Files:** `Dock/AppShortcut.swift`

Add an optional hex-string field. `nil` means "auto" (existing behaviour).

```swift
struct AppShortcut: Identifiable, Codable, Equatable {
    // ... existing fields ...
    var backgroundColorHex: String? = nil   // nil → auto-derive from icon
}
```

`Codable` handles the optional automatically — older saved shortcuts decode
without the field and get `nil`, so no migration is needed.

No change to `AppShortcutStore`, `DockItem`, or any persistence logic.

---

## Phase 2 — UI: color picker row in `ShortcutSheet`

**Files:** `Settings/ShortcutSheet.swift`

### 2a. New state variables

```swift
@State private var customBackgroundEnabled: Bool  = false
@State private var customBackgroundColor:   Color = .gray
```

### 2b. Populate on appear (edit mode)

```swift
if let hex = shortcut.backgroundColorHex {
    customBackgroundEnabled = true
    customBackgroundColor   = ColorUtils.fromHex(hex)
}
```

### 2c. New form row (after the custom-label row)

```swift
formRow(label: "Background") {
    Toggle("Custom", isOn: $customBackgroundEnabled)
        .onChange(of: customBackgroundEnabled) { _, enabled in
            if enabled && customBackgroundColor == .gray,
               let image = selectedIconImage,
               let derived = ColorUtils.averageColor(of: image) {
                customBackgroundColor = derived
            }
        }
    if customBackgroundEnabled {
        ColorPicker("", selection: $customBackgroundColor, supportsOpacity: false)
            .labelsHidden()
            .frame(width: 32)
    }
}
```

When the toggle is turned on for the first time, the picker seeds itself from
the icon's auto-derived color (same source used at runtime) so the user starts
from a familiar reference point. Falls back to gray if no icon is loaded yet.

### 2d. Pass through `save()`

In both `saveNew()` and `saveExisting()`, set the field before calling `onSave`:

```swift
newShortcut.backgroundColorHex = customBackgroundEnabled
    ? ColorUtils.toHex(customBackgroundColor)
    : nil
```

No UI changes needed elsewhere — `onSave` already flows through
`AppShortcutStore.save`.

---

## Phase 3 — Rendering: `AppShortcutButton` respects the override

**Files:** `Dock/AppShortcutButton.swift`

### Color resolution rule

> **If `backgroundColorHex` is non-nil, use it. Otherwise always use the
> average color derived from the icon.** There is no third state — the
> `@State private var avgColor` property always ends up set to one of these two
> sources before the view renders.

### 3a. Resolve display color after icon load

At the end of `loadIcon()`, always compute the average color first, then
replace it with the override only if one is set:

```swift
cachedIcon     = result.0
cachedIconFull = result.1
avgColor       = result.2                           // always set from icon first

if let hex = shortcut.backgroundColorHex {
    avgColor = ColorUtils.fromHex(hex)              // override wins if present
}
```

When `backgroundColorHex == nil`, `avgColor` stays as the derived average —
nothing extra is needed. `avgColor` continues to drive the background fill,
window indicator, and frontmost-app border with no further changes.

### 3b. Re-apply when only the color changes

The existing `.task(id: shortcut.iconFileName)` re-runs `loadIcon()` when the
icon file changes (which covers both sources above). Add a second task so that
editing just the color — without changing the icon — also updates immediately:

```swift
.task(id: shortcut.backgroundColorHex) {
    if let hex = shortcut.backgroundColorHex {
        avgColor = ColorUtils.fromHex(hex)          // override applied
    } else {
        // nil → re-derive from the cached icon so the average is restored
        // without re-fetching the file
        if let image = NSImage(contentsOf: AppShortcutStore.iconURL(for: shortcut.iconFileName)),
           let derived = ColorUtils.averageColor(of: image) {
            avgColor = derived
        }
    }
}
```

This ensures clearing the override (toggling it off in the sheet) restores the
average color without waiting for a full `loadIcon()` cycle.

---

## Phase 4 — Reset and edge cases

**Files:** `Settings/SettingsView.swift`

### 4a. `resetToDefaults()`

No change needed. `resetToDefaults()` does not touch individual shortcuts —
it resets global `UserDefaults` keys only. Shortcuts are stored separately via
`AppShortcutStore`.

### 4b. Color picker preview in `IconPickerButton` (optional polish)

`IconPickerButton` currently shows the icon image only. A small improvement: if
`customBackgroundEnabled` is true, wrap the icon in a
`RoundedRectangle.fill(customBackgroundColor)` background in the picker so the
user sees a live preview of how the icon will look in the dock.

This is visual-only and does not affect data or logic.

---

## File change summary

| Phase | File | Change |
|---|---|---|
| 1 | `Dock/AppShortcut.swift` | Add `backgroundColorHex: String? = nil` |
| 2 | `Settings/ShortcutSheet.swift` | Add toggle + `ColorPicker` form row; thread value through `save()` |
| 3 | `Dock/AppShortcutButton.swift` | Override `avgColor` after load; add `.task` for color-only updates |
| 4 (optional) | `Settings/ShortcutSheet.swift` | Background-color preview in `IconPickerButton` area |

---

## Testing checklist

- [ ] New shortcut added without enabling override — `backgroundColorHex` is `nil`,
      background auto-derives from icon as before
- [ ] New shortcut with override enabled — color picker value is saved and
      background renders correctly in dock
- [ ] Edit existing shortcut (no prior override) — toggle defaults to off,
      enabling it seeds picker from derived color
- [ ] Edit existing shortcut (prior override set) — toggle defaults to on,
      picker shows saved color
- [ ] Disable override on an existing shortcut that had one — `backgroundColorHex`
      clears to `nil`, background auto-derives again
- [ ] Older saved shortcuts (without the field) load without error and auto-derive
      as before
- [ ] Color-only edit (icon unchanged) — `.task(id: backgroundColorHex)` triggers
      and updates dock immediately without re-loading icon
- [ ] `showIconBackground = false` — no background is rendered regardless of override
- [ ] Window indicator and frontmost border both use the custom color
