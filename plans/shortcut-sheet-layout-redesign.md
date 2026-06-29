# DeskMat — ShortcutSheet Layout Redesign

Refactor the Add/Edit Shortcut dialog from a single-column stacked form into a
two-column layout that puts the icon on the left, form fields on the right, and
moves the Remove button + color picker into the footer row.

---

## Target layout (from mockup)

```
┌──────────────────────────────────────────────┐
│                                              │
│   ┌──────────┐   ┌──────────────────────┐   │
│   │          │   │  Application row     │   │
│   │   Icon   │   │  Label row           │   │
│   │ (large)  │   │                      │   │
│   └──────────┘   └──────────────────────┘   │
│                                              │
├──────────────────────────────────────────────┤
│  [Remove]   [Color ◼]        [Cancel] [Save] │
└──────────────────────────────────────────────┘
```

- **Left column**: enlarged `IconPickerButton` (~100 × 100)
- **Right column**: Application + Label form fields, vertically stacked
- **Footer row**: Remove pill (edit mode only) • Color swatch • Cancel • Save
- Color picker moves out of the form body and into the footer
- **No rounded card** — the content area renders directly on the window background with no card background, shadow, or clip shape

---

## Current state

- `ShortcutSheet` is a vertical single-column form
- Header: icon picker centered at top
- Body card: Application row, Label row, Color row — wrapped in a `RoundedRectangle` with `.background(.background)`, `.clipShape`, and `.shadow`
- Footer: [Cancel] [Save]
- No remove action exists in the sheet (remove is only via dock context menu)
- `ShortcutSheet` has no `onRemove` callback
- No `shortcutRemoved` notification name exists

---

## Phase 1 — Two-column content layout

**Files:** `Settings/ShortcutSheet.swift`

Replace the current `VStack` body with an `HStack` at the top of the content
area. **Remove the rounded card entirely** — delete the `.background(.background)`,
`.clipShape(RoundedRectangle(...))`, `.shadow(...)`, and `.padding(16)` modifiers
that currently wrap the form body. Content renders directly on the window's
native background with no card, no shadow, and no clip.

### Left column
- `IconPickerButton` enlarged to **100 × 100** (up from 64 × 64)
- Fixed width column, vertically top-aligned
- Centered horizontally within its column

### Right column
- `formRow` for Application (unchanged logic)
- `formRow` for Label (unchanged logic)
- The Color row is **removed from here** (moves to footer in Phase 2)
- Column takes remaining width, top-aligned

### `formRow` helper
The current `formRow` uses a 72 pt label column. In the new right-column layout
the label column will need to be narrower to fit. Adjust label width to **60 pt**.

### Overall structure change
```swift
// Before
VStack(spacing: 0) {
    // header (icon centered)
    // card (form rows)
}

// After
VStack(spacing: 0) {
    HStack(alignment: .top, spacing: 16) {
        // left: icon
        // right: form rows
    }
    .padding(20)
}
```

The card background / shadow wraps the HStack, not each column independently.

---

## Phase 2 — Footer: color + remove + actions in one row

**Files:** `Settings/ShortcutSheet.swift`

Replace the current footer (error text + HStack of buttons) with a single
`HStack` that holds all footer elements:

```
[Remove]   [◼ ColorPicker]   <Spacer>   [Cancel]  [Save]
```

### Remove button
- A `Button` with label "Remove", styled as a red filled capsule/pill
- **Only shown in edit mode** (`isEditing == true`)
- Calls a new `onRemove` closure (added in Phase 3)
- Uses a confirmation dialog (`confirmationDialog`) before firing, to prevent
  accidental deletion

### Color picker
- `ColorPicker("", selection: $customBackgroundColor, supportsOpacity: false)`
  with `.labelsHidden()`
- Move it here from the form body (remove the "Color" `formRow`)
- Sits directly to the right of the Remove button (or at the leading edge
  in add mode)
- Optionally show the current hex string as a `Text` next to the swatch
  (matching the "#000000" label in the mockup)

### Error message
- If an `errorMessage` is set, show it above the footer row (same as today)

### Updated footer layout
```swift
VStack(spacing: 6) {
    if let error = errorMessage { ... }
    HStack(spacing: 10) {
        if isEditing {
            removeButton   // red pill
        }
        colorPickerSwatch
        Spacer()
        cancelButton
        saveButton
    }
}
.padding(20)
```

---

## Phase 3 — Remove shortcut wiring

**Files:**
- `Core/NotificationNames.swift`
- `Settings/ShortcutSheet.swift`
- `App/AppDelegate+Windows.swift`

### 3a. New notification name

```swift
static let shortcutRemoved = Notification.Name("shortcutRemoved")
```

The notification object will be the `AppShortcut` being removed, matching
the pattern of `shortcutEdited`.

### 3b. `onRemove` callback on `ShortcutSheet`

```swift
let onRemove: (() -> Void)?   // nil in add mode — button hidden
```

Called after the confirmation dialog is accepted.

### 3c. Wire in `AppDelegate+Windows`

In `editShortcut(_:)`, pass a closure that posts the notification and closes
the window:

```swift
let editView = ShortcutSheet(
    shortcut: shortcut,
    onSave: { ... },
    onDismiss: { ... },
    onRemove: { [weak self] in
        NotificationCenter.default.post(name: .shortcutRemoved, object: shortcut)
        self?.editShortcutWindow?.close()
        self?.editShortcutWindow = nil
    }
)
```

`addShortcut()` passes `onRemove: nil` (no change needed since the button is
hidden when `onRemove` is nil).

### 3d. Handle in dock / store

Wherever `shortcutEdited` is observed (the dock view or store), add a matching
observer for `shortcutRemoved` that calls the existing remove logic.

---

## Phase 4 — Visual polish

**Files:** `Settings/ShortcutSheet.swift`, `Dock/IconPickerButton.swift`

### 4a. `IconPickerButton` size

Update the picker to support a configurable size instead of hardcoded `64`/`48`.
Pass `size: CGFloat = 64` and use it throughout so Phase 1 can pass `size: 100`.
The badge offsets (`x: 10, y: 5` / `x: -10, y: -6`) scale with the larger frame.

### 4b. Window width

The new two-column layout needs more horizontal room than the current 460 pt.
`makeStandardWindow` is called with a `width` parameter. Update the call for the
shortcut sheet to **520 pt** to give both columns comfortable room.

### 4c. Separator

Keep the `Divider()` between the content area and the footer.

### 4d. Confirmation dialog for Remove

Attach `.confirmationDialog` to the remove button to match the macOS HIG for
destructive actions:

```swift
.confirmationDialog("Remove \(shortcut.displayName)?", isPresented: $showRemoveConfirm, titleVisibility: .visible) {
    Button("Remove", role: .destructive) { onRemove?() }
    Button("Cancel", role: .cancel) { }
}
```

---

## File change summary

| Phase | File | Change |
|---|---|---|
| 1 | `Settings/ShortcutSheet.swift` | HStack two-column layout; remove rounded card (background, clipShape, shadow, padding); adjust `formRow` label width |
| 2 | `Settings/ShortcutSheet.swift` | Footer: color picker + remove button + action buttons in one row |
| 3 | `Core/NotificationNames.swift` | Add `shortcutRemoved` |
| 3 | `Settings/ShortcutSheet.swift` | Add `onRemove: (() -> Void)?` parameter |
| 3 | `App/AppDelegate+Windows.swift` | Wire `onRemove` in `editShortcut(_:)` |
| 3 | Dock/store observer | Handle `shortcutRemoved` notification |
| 4 | `Dock/IconPickerButton.swift` | Configurable `size` parameter |
| 4 | `App/AppDelegate+Windows.swift` | Widen shortcut sheet window to 520 pt |

---

## Testing checklist

- [ ] Add mode: two-column layout renders, no Remove button visible
- [ ] Edit mode: Remove button appears, confirmation dialog fires before removal
- [ ] Color swatch in footer reflects live changes (same as current color row)
- [ ] Icon preview in icon picker reflects background color (Phase 4 of prior plan)
- [ ] Larger icon (100×100) renders without distortion in both add and edit modes
- [ ] Icon reset (`xmark.circle`) badge repositions correctly at larger size
- [ ] Window resizes to fit new layout on open
- [ ] Removing a shortcut via the sheet closes the window and removes from dock
- [ ] Removing a shortcut via the dock context menu still works (unchanged path)
- [ ] Error message still appears above the footer row
