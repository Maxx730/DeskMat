# Plan: Confirm Modal on Folder Delete

## Goal

Show a confirmation alert before removing a folder from the dock. Folders can contain many apps, so an accidental tap on "Remove Folder" in the context menu would silently delete all of them. The guard should be proportional — show how many apps are inside so the user knows what they're about to lose.

---

## Current Flow

1. User right-clicks a folder → context menu appears in `FolderButton.swift:86-89`
2. Tapping "Remove Folder" fires `onRemove()` immediately
3. `ContentView.removeItem(_:)` calls `AppShortcutStore.deleteIcons(for:)` then removes the item — no prompt

---

## Proposed Flow

1. User taps "Remove Folder" in the context menu
2. A SwiftUI `.alert` fires **before** deletion — it names the folder and shows the app count
3. The user either confirms (destructive) or cancels
4. Confirmation triggers the existing `removeItem(_:)` logic unchanged

---

## Implementation Steps

### 1. Add pending-delete state to `ContentView`

```swift
@State private var folderPendingDelete: DockItem? = nil
```

This holds the folder the user wants to delete. `nil` means no alert is shown.

### 2. Wire the context menu to set state instead of delete directly

In `ContentView.dockItemView()` (around line 197), change the `onRemove` closure for folder items:

```swift
// Before
onRemove: { removeItem(item) }

// After — only set pending state; actual delete happens in the alert action
onRemove: { folderPendingDelete = item }
```

App shortcut items keep the existing direct-delete behaviour unchanged.

### 3. Attach the alert to the dock's root view

Add the `.alert` modifier on the outermost view in `ContentView.body` (the `ZStack`), alongside the existing modifiers:

```swift
.alert(
    "Remove \"\(folderName)\"?",
    isPresented: Binding(
        get: { folderPendingDelete != nil },
        set: { if !$0 { folderPendingDelete = nil } }
    )
) {
    Button("Remove", role: .destructive) {
        if let item = folderPendingDelete { removeItem(item) }
        folderPendingDelete = nil
    }
    Button("Cancel", role: .cancel) {
        folderPendingDelete = nil
    }
} message: {
    Text(alertMessage)
}
```

Where `folderName` and `alertMessage` are computed from `folderPendingDelete`.

### 4. Add computed helpers in `ContentView`

```swift
private var folderDeleteName: String {
    if case .folder(let f) = folderPendingDelete { return f.name }
    return "Folder"
}

private var folderDeleteMessage: String {
    guard case .folder(let f) = folderPendingDelete else { return "" }
    let count = f.shortcuts.count
    if count == 0 {
        return "This folder is empty."
    } else {
        return "This will remove the folder and its \(count) app\(count == 1 ? "" : "s") from the dock."
    }
}
```

### 5. Add strings to `Strings.swift` (optional but preferred)

Follow the existing `Strings` enum pattern:

```swift
enum FolderDelete {
    static let title = "Remove Folder?"
    static let confirm = "Remove"
    static let emptyMessage = "This folder is empty."
    static func message(count: Int) -> String {
        "This will remove the folder and its \(count) app\(count == 1 ? "" : "s") from the dock."
    }
}
```

---

## Files Changed

| File | Change |
|------|--------|
| `ContentView.swift` | Add `@State var folderPendingDelete`, update `onRemove` closure for folders, add `.alert` modifier, add two computed helpers |
| `Strings.swift` | Add `Strings.FolderDelete` namespace with title, confirm label, and message factory |
| `FolderButton.swift` | No changes needed — `onRemove` is already a callback |

---

## What Stays the Same

- App shortcut deletion — still fires immediately, no confirmation
- `removeItem(_:)` — called identically after confirmation, no changes needed
- Drag-to-reorder — unaffected
- The context menu UI in `FolderButton` — "Remove Folder" label and `.destructive` role stay as-is

---

## Edge Cases

- **Empty folder** — alert still shows, message says "This folder is empty" so the user can still confirm
- **Multiple rapid taps** — setting `folderPendingDelete` twice just replaces the value; only one alert shows at a time
- **Dismissing via escape / outside tap** — the `set:` closure on the `Binding` resets `folderPendingDelete` to `nil`, leaving state clean
