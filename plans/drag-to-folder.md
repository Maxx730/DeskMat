# Plan: Drag-to-Folder

Dragging one dock item onto another creates a folder containing both, mirroring the iOS/macOS home screen gesture. If the target is an existing folder, the dragged item is added to it instead.

---

## Current drag system recap

`ContentView` owns all drag state:
- `dragStart` — captures the item, builds `displayItems` (nil gap array), installs a global mouse monitor
- `dragChanged` — recomputes `targetIndex` (gap position) from cursor x
- `dragEnd` — commits the reorder or cancels

The system currently has two modes: **idle** and **reordering**. This plan adds a third: **merging**.

---

## Phase 1 — Detect "drop onto" vs "drop between"

**Goal:** determine whether the cursor is hovering over an icon body or in the gap between icons.

Each slot is `cellSize + hstackItemSpacing = 72pt` wide. An icon body occupies the center 64pt of that slot. The 8pt gap between icons is the only true "between" space.

**Approach:** compute the cursor's distance from the nearest icon center. If the distance is within `cellSize * 0.45` (≈ 28.8pt — inside the icon body, not in the gap), treat as a "drop onto" gesture. Otherwise fall through to the existing reorder logic.

**New state in ContentView:**
```swift
@State private var dropTargetID: UUID? = nil
```

**Updated `dragChanged` logic:**
1. Compute `nearestIconIndex` and its center x position
2. If `|localX - center| < cellSize * 0.45` AND `nearestIcon.id != draggingItem.id`:
   - Set `dropTargetID = nearestIcon.id`
   - Restore `displayItems` to all items without a gap (no reorder shown)
3. Else:
   - Clear `dropTargetID = nil`
   - Proceed with existing gap/reorder logic

The two modes are mutually exclusive — when `dropTargetID` is set, the gap animation is suppressed.

---

## Phase 2 — Dwell timer (prevent accidental merges)

**Goal:** only commit to "merge mode" if the user holds over an icon for ≥ 0.5 seconds, not just passes over it.

**New state:**
```swift
@State private var mergeConfirmed: Bool = false
private var dwellWorkItem: DispatchWorkItem?
```

**Logic:**
- When `dropTargetID` is set to a new value: cancel any existing `dwellWorkItem`, schedule a new one for 0.5s that sets `mergeConfirmed = true`
- When `dropTargetID` is cleared: cancel `dwellWorkItem`, set `mergeConfirmed = false`
- Visual feedback only activates once `mergeConfirmed = true`

---

## Phase 3 — Visual feedback

**Target icon** (the one being hovered over, once `mergeConfirmed`):
- Animated pulsing ring: `RoundedRectangle.stroke(Color.white.opacity(0.7))` with a repeating scale animation
- Slight scale-up (`scaleEffect(1.08)`) to indicate it's "active"

**Drag ghost** (`DragGhostIcon`):
- When `mergeConfirmed`: overlay a small folder badge (`Image(systemName: "folder.badge.plus")`) in the bottom-right corner

**Implementation:** pass `isDropTarget: Bool` and `mergeConfirmed: Bool` into `dockItemView`. The target icon applies the ring modifier conditionally. `DragGhostIcon` receives a `showFolderBadge: Bool` parameter.

---

## Phase 4 — Folder creation on drop

**In `dragEnd`**, before the existing reorder logic, check `dropTargetID`:

```
if dropTargetID != nil && mergeConfirmed:
    handle merge
    return early (skip reorder)
```

**Merge combinations:**

| Dragged | Target | Result |
|---|---|---|
| shortcut | shortcut | New folder containing both shortcuts. Auto-named "New Folder". |
| shortcut | folder | Shortcut appended to folder's shortcuts (if not already present). |
| folder | shortcut | Shortcut appended to dragged folder's shortcuts. Dragged folder replaces both positions. |
| folder | folder | Target folder's shortcuts appended to dragged folder. Dragged folder replaces both. |

**After merge:** remove both original items from `items`, insert the resulting folder at the lower of the two original indices. Save. Clear all drag state.

---

## Phase 5 — Auto-naming

All new folders created via drag-to-merge are automatically named `"New Folder"`. No prompt is shown — the user can rename at any time via "Edit Folder…" in the context menu.

---

## Refactor notes

- No structural changes to `AppFolder`, `DockItem`, or `AppShortcutStore` are needed
- `dragChanged` grows moderately — consider extracting a `computeDragMode(at:)` helper that returns an enum `(.reorder(Int), .merge(UUID))` to keep the function readable
- `DragGhostIcon` needs one new parameter: `showFolderBadge: Bool`
- `dockItemView` needs `isDropTarget: Bool` and `mergeConfirmed: Bool` passed through so target icons can render the ring
- The dwell `DispatchWorkItem` must be stored as a class-level property (not `@State`) to avoid retain cycles — same pattern as `dragMonitorToken`
