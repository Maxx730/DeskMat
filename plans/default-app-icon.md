# Default New Shortcut Icon to App's Actual Icon

## Goal

When a user picks an app in the add/edit shortcut sheet, automatically populate the icon
preview with that app's real icon (via `NSWorkspace`). The user can still tap the icon to
replace it with a custom image. Previously, the icon area was always blank until the user
manually chose a file.

## Current Behaviour

`ShortcutSheet.pickApp()` reads the bundle name and bundle ID from the chosen `.app`
bundle, but does nothing with the app's icon. The icon preview stays empty and the Save
button stays disabled until the user also opens a separate file picker to choose an icon.

The seeding code in `AppShortcutStore.initializeWithDefaults()` already demonstrates the
correct `NSWorkspace` → `NSImage` → PNG pattern; we just need to bring the same approach
into the live add/edit flow.

## Approach

1. When an app is chosen in `pickApp()`, extract its icon from `NSWorkspace` and store it
   in `selectedIconImage` for display. Clear `selectedIconURL` (no file was picked).

2. Add `AppShortcutStore.copyIcon(from image: NSImage, for id: UUID) throws -> String` so
   the save path can persist an `NSImage` directly without needing a temp file URL.

3. Update `saveNew()` to accept either a URL source or an `NSImage` source.

4. Update `saveExisting()` to handle the same — when the user picks a different app while
   editing, `iconChanged` is set and the new icon comes from `NSImage`, not a URL.

5. Relax the Save button's disabled condition so it enables as soon as both an app and an
   icon image are present (regardless of whether the icon came from a URL or `NSWorkspace`).

## Files to Change

### `DeskMat/AppShortcutStore.swift`

Add one new static method alongside the existing `copyIcon(from:for:)`:

```swift
static func copyIcon(from image: NSImage, for shortcutID: UUID) throws -> String {
    try ensureDirectories()
    guard
        let tiffData = image.tiffRepresentation,
        let bitmap   = NSBitmapImageRep(data: tiffData),
        let pngData  = bitmap.representation(using: .png, properties: [:])
    else { throw CocoaError(.fileWriteUnknown) }
    let fileName = "\(shortcutID.uuidString).png"
    try pngData.write(to: iconsDirectory.appending(path: fileName), options: .atomic)
    return fileName
}
```

This mirrors the conversion already used in `initializeWithDefaults`.

---

### `DeskMat/ShortcutSheet.swift`

**`pickApp()` — auto-load the app icon after the user selects an app**

After `selectedBundleID` is set, add:

```swift
let icon = NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false))
selectedIconImage = icon
selectedIconURL   = nil   // icon came from NSWorkspace, not a user-picked file
if isEditing { iconChanged = true }
```

**`pickIcon()` — no change in behaviour, but `selectedIconURL` is set as before**

When the user manually picks a file, `selectedIconURL` is set and `selectedIconImage` is
updated from that file. The existing logic is unchanged.

**`saveNew()` — accept image source when no URL is present**

Replace the guard that requires `selectedIconURL` with logic that handles both sources:

```swift
private func saveNew() {
    guard let appURL = selectedAppURL, !selectedBundleID.isEmpty else {
        errorMessage = Strings.Errors.selectBothAppAndIcon
        return
    }
    let shortcutID = UUID()
    do {
        let iconFileName: String
        if let url = selectedIconURL {
            iconFileName = try AppShortcutStore.copyIcon(from: url, for: shortcutID)
        } else if let image = selectedIconImage {
            iconFileName = try AppShortcutStore.copyIcon(from: image, for: shortcutID)
        } else {
            errorMessage = Strings.Errors.selectBothAppAndIcon
            return
        }
        let newShortcut = AppShortcut(
            displayName: selectedAppName,
            bundleIdentifier: selectedBundleID,
            appURL: appURL,
            iconFileName: iconFileName,
            customLabel: customLabel.isEmpty ? nil : customLabel
        )
        onSave(newShortcut)
    } catch {
        errorMessage = Strings.Errors.failedToSaveIcon(error.localizedDescription)
    }
}
```

**`saveExisting()` — handle NSImage source when icon was changed via app re-pick**

Inside the `iconChanged` branch, add the NSImage fallback:

```swift
if iconChanged {
    AppShortcutStore.deleteIcon(named: shortcut.iconFileName)
    if let url = selectedIconURL {
        iconFileName = try AppShortcutStore.copyIcon(from: url, for: UUID())
    } else if let image = selectedIconImage {
        iconFileName = try AppShortcutStore.copyIcon(from: image, for: UUID())
    }
}
```

**Save button disabled condition**

Change the `isEditing ? ... : ...` expression so that in the add flow the button enables
whenever an app and any icon (URL or NSImage) are both present:

```swift
.disabled(
    isEditing
        ? selectedBundleID.isEmpty
        : (selectedAppURL == nil || (selectedIconURL == nil && selectedIconImage == nil))
)
```

## State After the Change

| User action | `selectedIconImage` | `selectedIconURL` | `iconChanged` |
|---|---|---|---|
| Opens sheet (add) | nil | nil | false |
| Picks an app | app icon from NSWorkspace | nil | false |
| Manually picks a custom icon | image from file | file URL | true |
| Picks a different app (edit) | new app icon | nil | true |
| Manually picks a custom icon (edit) | image from file | file URL | true |

## What Does Not Change

- Custom icon picking via `pickIcon()` works exactly as before.
- The edit flow's `iconChanged` flag logic is preserved.
- Export/import (`.dskm`) is unaffected — icons are already stored as files in the icons
  directory before export.
- No new `@State` variables are needed; the existing `selectedIconImage` / `selectedIconURL`
  pair is sufficient to express all cases.
