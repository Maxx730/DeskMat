# Reset Icon Button

Add a small reset button to the icon picker in both `ShortcutSheet` and `FolderSheet` so the user can remove a custom icon and revert to the default.

---

## Background

### Icon model differences
| Model | `iconFileName` type | "Default" state |
|---|---|---|
| `AppShortcut` | `String` (required) | Auto-extracted from app bundle at pick time |
| `AppFolder` | `String?` (optional) | `nil` → shows `FolderMiniGrid` in the dock |

### Current sheet state variables (relevant)
**ShortcutSheet**
- `selectedIconURL: URL?` — custom image the user picked via file panel
- `selectedIconImage: NSImage?` — icon auto-extracted from the `.app` bundle when app is chosen
- `iconChanged: Bool` — gates the save path that deletes the old file and writes a new one

**FolderSheet**
- `customIconURL: URL?` — custom image the user picked via file panel
- `iconFileName: String?` — propagated to the saved `AppFolder`; `nil` = no custom icon

### AppShortcutStore helpers needed
- `copyIcon(from: NSImage, for: UUID) throws -> String` — already exists
- `deleteIcon(named: String)` — already exists

---

## Phases

### Phase 1 — FolderSheet reset button

The simplest case: `iconFileName` is optional, so resetting just means clearing it.

**What "has a custom icon" means:**
- `customIconURL != nil` (user picked one this session), OR
- `folder != nil && folder!.iconFileName != nil` (editing an existing folder that has one)

**State change:**
Track whether the icon should be cleared on save with a new flag:
```swift
@State private var iconCleared = false
```

**Reset action:**
```swift
customIconURL = nil
iconCleared = true
```

**Save path — add before constructing the `AppFolder`:**
```swift
if iconCleared, let oldName = folder?.iconFileName {
    AppShortcutStore.deleteIcon(named: oldName)
    iconFileName = nil
}
```

**UI:** Overlay a small `xmark.circle.fill` button at the top-trailing corner of the 64×64 icon picker button. Show it only when `hasCustomIcon` (the computed property above) is true.

```swift
private var hasCustomIcon: Bool {
    customIconURL != nil || (folder?.iconFileName != nil && !iconCleared)
}
```

---

### Phase 2 — ShortcutSheet reset button

Slightly more complex: `iconFileName` is required, so reset means reverting to the auto-extracted app icon rather than removing the icon entirely.

**What "has a custom icon" means:**
The user explicitly opened the file panel and picked a non-app-bundle image:
```swift
private var hasCustomIcon: Bool { selectedIconURL != nil }
```

**Reset action — re-extract the app icon from the bundle:**
```swift
func resetToAppIcon() {
    guard let appURL = selectedAppURL ?? shortcut?.appURL else { return }
    let nsImage = NSWorkspace.shared.icon(forFile: appURL.path)
    selectedIconImage = nsImage
    selectedIconURL = nil   // clears the custom path
    iconChanged = true      // ensures old custom file is deleted on save
}
```

The existing save path already handles `iconChanged == true` + `selectedIconURL == nil` + `selectedIconImage != nil`:
```swift
} else if let image = selectedIconImage {
    iconFileName = try AppShortcutStore.copyIcon(from: image, for: UUID())
}
```
No save-path changes needed.

**UI:** Same overlay pattern — `xmark.circle.fill` at the top-trailing corner of the icon picker button, visible only when `hasCustomIcon`.

---

### Phase 3 — Shared icon picker overlay component

Both sheets use an identical 64×64 icon button with a pencil badge. Extract this into a small reusable `IconPickerButton` view to avoid duplicating the reset overlay logic:

```swift
struct IconPickerButton: View {
    let image: NSImage?
    let placeholder: AnyView         // shown when image == nil
    let hasCustomIcon: Bool
    let onPick: () -> Void
    let onReset: () -> Void

    var body: some View {
        Button(action: onPick) { ... }
        .overlay(alignment: .topTrailing) {
            if hasCustomIcon {
                Button(action: onReset) {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.6))
                        .font(.system(size: 16))
                }
                .buttonStyle(.plain)
                .offset(x: 6, y: -6)
            }
        }
    }
}
```

Replace the existing icon button in both sheets with `IconPickerButton`.

---

## File Checklist

| File | Change |
|---|---|
| `FolderSheet.swift` | Add `iconCleared` state, `hasCustomIcon` computed var, reset action, updated save path, reset overlay on icon button |
| `ShortcutSheet.swift` | Add `hasCustomIcon` computed var, `resetToAppIcon()` helper, reset overlay on icon button |
| `IconPickerButton.swift` (new, optional) | Shared component — only worth extracting once both sheets are updated |
| `Strings.swift` | Optional: add `Strings.Icons.resetIcon` if a tooltip/accessibility label is needed |

---

## Notes

- The `xmark.circle.fill` with palette rendering (white glyph / dark fill) stays visible on both light and dark icons.
- Reset does **not** immediately delete the file — deletion happens only in the save path, so the user can cancel and the old file is untouched.
- For new (unsaved) shortcuts there is no existing file to delete; reset in that case just clears `selectedIconURL` and the existing app-icon extraction path handles the rest.
