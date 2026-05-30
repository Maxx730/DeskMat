# Unit Tests — Branch Feature Coverage

All tests use the Swift Testing framework (`import Testing`, `@testable import DeskMat`, `@MainActor struct`, `@Test func`, `#expect`), matching the existing test suite conventions.

---

## Phase 1 — `updateShortcut` Folder Nesting

**File:** `DeskMatTests/UpdateShortcutTests.swift`

Tests the bug fix that made `updateShortcut` search inside folder contents, not just top-level items.

```
@Test func updatesTopLevelShortcut()
  - items = [.shortcut(a), .shortcut(b)]
  - call updateShortcut with modified version of a
  - #expect items[0] == .shortcut(modified a)

@Test func updatesShortcutInsideFolder()
  - items = [.folder(folder containing [a, b])]
  - call updateShortcut with modified version of a
  - extract folder from items[0], #expect folder.shortcuts[0] == modified a

@Test func doesNotMutateUnrelatedItems()
  - items = [.shortcut(x), .folder(folder containing [a, b])]
  - call updateShortcut for a
  - #expect items[0] == .shortcut(x) (unchanged)

@Test func noOpForUnknownID()
  - items = [.shortcut(a)]
  - call updateShortcut with shortcut whose id doesn't exist
  - #expect items unchanged
```

---

## Phase 2 — Drag-to-Merge Threshold (`computeDragMode`)

**File:** `DeskMatTests/DragModeTests.swift`

Tests the updated `mergeThreshold = cellSize * 0.6` and dwell time of 0.35s.

```
@Test func mergeWhenOverlapExceedsThreshold()
  - set up two item frames with overlap > 60% of cellSize
  - call computeDragMode
  - #expect result == .merge(targetIndex: ...)

@Test func noMergeWhenOverlapBelowThreshold()
  - overlap exactly at 59% of cellSize
  - #expect result == .reorder (not .merge)

@Test func mergeAtExactThreshold()
  - overlap exactly at 60% of cellSize
  - #expect result == .merge

@Test func reorderWhenDraggedToGap()
  - dragged item not overlapping any target above threshold
  - #expect result == .reorder
```

---

## Phase 3 — FolderSheet Icon Reset

**File:** `DeskMatTests/FolderSheetIconTests.swift`

Tests `hasCustomIcon` and `resetIcon()` logic in `FolderSheet`.

```
@Test func hasCustomIconFalseWhenNilImage()
  - customIconImage = nil
  - #expect hasCustomIcon == false

@Test func hasCustomIconTrueWhenImageSet()
  - customIconImage = NSImage()
  - #expect hasCustomIcon == true

@Test func resetIconClearsImageAndURL()
  - customIconImage = NSImage(), customIconURL = someURL, iconChanged = false
  - call resetIcon()
  - #expect customIconImage == nil
  - #expect customIconURL == nil
  - #expect iconChanged == true

@Test func resetIconAllowsSavePathToNilIconFileName()
  - after resetIcon(), simulate save: iconChanged && customIconURL == nil
  - #expect resulting folder.iconFileName == nil
```

---

## Phase 4 — ShortcutSheet Icon Reset

**File:** `DeskMatTests/ShortcutSheetIconTests.swift`

Tests `hasCustomIcon` and `resetToAppIcon()` logic in `ShortcutSheet`.

```
@Test func hasCustomIconFalseForNewShortcutNoURL()
  - isEditing = false, selectedIconURL = nil
  - #expect hasCustomIcon == false

@Test func hasCustomIconTrueWhenURLPicked()
  - selectedIconURL = someURL
  - #expect hasCustomIcon == true

@Test func hasCustomIconTrueWhenEditingExistingShortcutWithImage()
  - isEditing = true, selectedIconImage = NSImage(), selectedIconURL = nil
  - #expect hasCustomIcon == true

@Test func resetToAppIconClearsURLAndSetsIconChanged()
  - selectedIconURL = someURL, iconChanged = false
  - call resetToAppIcon() (stub bundle extraction)
  - #expect selectedIconURL == nil
  - #expect iconChanged == true

@Test func resetToAppIconRestoresImageFromBundle()
  - shortcut has valid bundleID
  - call resetToAppIcon()
  - #expect selectedIconImage != nil
```

---

## Phase 5 — FolderMiniGrid Always Shows 4 Slots

**File:** `DeskMatTests/FolderMiniGridTests.swift`

Tests that `FolderMiniGrid` renders exactly 4 cells regardless of how many shortcuts are in the folder.

```
@Test func rendersFourSlotsForEmptyFolder()
  - FolderMiniGrid(shortcuts: [])
  - render via ImageRenderer or inspect view body
  - #expect exactly 4 cells present

@Test func rendersFourSlotsForTwoShortcuts()
  - FolderMiniGrid(shortcuts: [a, b])
  - #expect 2 icon cells + 2 placeholder cells

@Test func rendersFourSlotsForFourShortcuts()
  - FolderMiniGrid(shortcuts: [a, b, c, d])
  - #expect 4 icon cells, 0 placeholders

@Test func capsAtFourEvenIfMoreShortcutsExist()
  - FolderMiniGrid(shortcuts: [a, b, c, d, e])
  - #expect only 4 cells rendered (prefix(4) behavior)
```

---

## Phase 6 — Import/Export Pro Tier Gating

**File:** `DeskMatTests/ImportExportEntitlementTests.swift`

Tests that import and export actions are disabled for non-pro users.

```
@Test func exportDisabledForFreeTier()
  - entitlements.isPro = false
  - inspect ContentView context menu / button state
  - #expect export button isDisabled == true

@Test func exportEnabledForProTier()
  - entitlements.isPro = true
  - #expect export button isDisabled == false

@Test func importDisabledForFreeTier()
  - entitlements.isPro = false
  - #expect import button isDisabled == true

@Test func importEnabledForProTier()
  - entitlements.isPro = true
  - #expect import button isDisabled == false
```

---

## Phase 7 — FolderExpansionPanel Background Config Passthrough

**File:** `DeskMatTests/FolderExpansionPanelTests.swift`

Tests that background config values are correctly passed from `ContentView` through `FolderExpansionPanel.show()` into `FolderExpansionView`.

```
@Test func showPassesDockBackgroundToView()
  - call FolderExpansionPanel.shared.show(..., dockBackground: .color, ...)
  - inspect hostingView.rootView.dockBackground
  - #expect == .color

@Test func showPassesColorHexToView()
  - call show(..., dockBackgroundColorHex: "#FF0000", ...)
  - #expect rootView.dockBackgroundColorHex == "#FF0000"

@Test func showPassesCornerRadiusToView()
  - call show(..., dockCornerRadius: 20.0, ...)
  - #expect rootView.dockCornerRadius == 20.0

@Test func showPassesReactiveStyleToView()
  - call show(..., reactiveStyle: .aurora, ...)
  - #expect rootView.reactiveStyle == .aurora

@Test func showPassesLimitFPSToView()
  - call show(..., limitReactiveFPS: true, ...)
  - #expect rootView.limitReactiveFPS == true
```

---

## Phase 8 — `FirstMouseHostingView.acceptsFirstMouse`

**File:** `DeskMatTests/FirstMouseHostingViewTests.swift`

Verifies the one behavioral guarantee of the new class.

```
@Test func acceptsFirstMouseReturnsTrue()
  - let view = FirstMouseHostingView(rootView: EmptyView())
  - #expect view.acceptsFirstMouse(for: nil) == true

@Test func superclassReturnsFlase()
  - let base = NSHostingView(rootView: EmptyView())
  - #expect base.acceptsFirstMouse(for: nil) == false
  // documents why the subclass was needed
```

---

## Implementation Order

| Phase | File | Complexity |
|---|---|---|
| 1 | UpdateShortcutTests | Low — pure logic, no UI |
| 2 | DragModeTests | Low — pure geometry logic |
| 3 | FolderSheetIconTests | Medium — SwiftUI view state |
| 4 | ShortcutSheetIconTests | Medium — SwiftUI view state |
| 5 | FolderMiniGridTests | Medium — view rendering |
| 6 | ImportExportEntitlementTests | Low — flag check |
| 7 | FolderExpansionPanelTests | High — singleton NSPanel |
| 8 | FirstMouseHostingViewTests | Low — one-liner override |

Start with phases 1, 2, 8 — they are pure logic or trivially verifiable and will build confidence before tackling the UI-heavy phases.
