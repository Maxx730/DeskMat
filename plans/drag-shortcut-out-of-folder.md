# Plan: Drag Shortcut Out of a Folder onto the Dock

## Goal

Let users long-press an app shortcut inside an open folder and drag it out, dropping it onto the dock as a top-level item. The experience should mirror the existing dock drag-to-reorder: a floating ghost icon follows the mouse, the dock shows a live gap indicating the drop position, and on release the shortcut is inserted at that index and removed from the source folder.

---

## Architecture Overview

The folder expansion panel (`FolderExpansionPanel`) is a separate `NSPanel` from the dock. The dock's drag system lives entirely inside `ContentView` and is scoped to dock items. A cross-panel drag therefore needs three things the current system lacks:

1. A **screen-level ghost panel** that can float above both panels simultaneously.
2. A **shared drag coordinator** that lets `FolderExpansionView` initiate a drag that `ContentView` finishes.
3. **Drop logic** in `ContentView` that knows how to extract a shortcut from its source folder and insert it into the top-level `items` array.

Once `DragGhostPanel` exists (Phase 2), the dock's own drag system should be migrated to use it too (Phase 3). This removes the only remaining case where a ghost is rendered inside a window's SwiftUI view hierarchy, making `DragGhostPanel` the single canonical ghost renderer across all drag interactions in the app.

---

## Phases

---

### Phase 1 — Wire long-press in FolderExpansionView

**Scope:** `FolderExpansionView.swift`, `FolderExpansionPanel.swift`

**Current state:**  
`AppShortcutButton.onDragStart` is stubbed `{ _ in }` for every shortcut inside `FolderExpansionView`. Long-pressing a folder shortcut today does nothing.

**Changes:**

1. Add a new callback parameter to `FolderExpansionView`:
   ```swift
   var onItemDragStart: (AppShortcut, AppFolder, Image?) -> Void = { _, _, _ in }
   ```

2. Wire each `AppShortcutButton.onDragStart` to call it, forwarding the shortcut, its parent folder, and the icon image.

3. Pass this callback through `FolderExpansionPanel.show(...)`. The caller (ContentView) will supply the real implementation in Phase 3.

**Result:** Long-pressing a folder shortcut calls a closure with `(AppShortcut, AppFolder, Image?)`. Nothing visual happens yet.

---

### Phase 2 — DragGhostPanel (floating screen-level ghost)

**Scope:** New file `DragGhostPanel.swift`

**Why a separate panel:**  
`DragGhostIcon` currently lives in `ContentView`'s `ZStack`, which is clipped to the dock window. A shortcut dragged from the folder panel would disappear as soon as it left the dock's bounds. A dedicated `NSPanel` at a high window level floats above everything and can follow the cursor across both panels.

**Implementation:**

1. Create `DragGhostPanel` as a singleton `NSPanel`:
   - Style: `.borderless`, `.nonactivatingPanel`
   - Level: `.floating + 2` (above folder panel at `floating + 1`)
   - Background: transparent, `isOpaque = false`, `hasShadow = false`
   - Size: 72 × 72 pt

2. Host a `DragGhostIcon` SwiftUI view inside it (same view already used in the dock).

3. Expose:
   ```swift
   func show(icon: Image?, at screenPoint: CGPoint)
   func move(to screenPoint: CGPoint)
   func hide()
   ```

4. `move(to:)` updates `frame.origin` directly (no animation) for tight cursor tracking.

**Result:** A ghost icon can float anywhere on screen, independent of either panel.

---

### Phase 3 — Migrate dock drag to DragGhostPanel

**Scope:** `ContentView.swift`

**Current state:**  
The dock renders its drag ghost as a `DragGhostIcon` view inside the `ZStack` in `body`, positioned with `.position(x: dragPosition.x, y: dragPosition.y)`. This ghost is in window-local coordinates and is clipped to the dock window's bounds. It works for dock-only drags but is inconsistent with the screen-level `DragGhostPanel` introduced in Phase 2.

**Changes:**

1. **`dragStart()`** — after capturing `draggingIcon`, call `DragGhostPanel.shared.show(icon: icon, at: screenPoint)` where `screenPoint` is the current `NSEvent.mouseLocation` (already available). Remove the assignment to `draggingIcon` state.

2. **`dragChanged()`** — replace the `dragPosition = newLocalPoint` update with `DragGhostPanel.shared.move(to: NSEvent.mouseLocation)`. The ghost now tracks in screen coordinates.

3. **Shaking** — `isShaking` state is currently toggled in `dragStart`. Move ownership to `DragGhostPanel`: call `DragGhostPanel.shared.startShaking()` at the same point. Remove the `@State private var isShaking` from `ContentView`.

4. **`dragEnd()`** — replace setting `draggingItem = nil` (which hid the ghost) with `DragGhostPanel.shared.hide()`.

5. **Remove from body** — delete the `if draggingItem != nil { DragGhostIcon(...) }` block from the `ZStack`. The ghost is now fully owned by the panel.

6. **State cleanup** — `draggingIcon: Image?` and `isShaking: Bool` can be removed from `ContentView` since `DragGhostPanel` owns them.

**Result:** Both drag flows (dock reorder and folder-to-dock) render their ghost through `DragGhostPanel`. The dock's ZStack no longer contains any ghost rendering code.

---

### Phase 4 — DragCoordinator (shared observable state)

**Scope:** New file `DragCoordinator.swift`, `ContentView.swift`, `FolderExpansionPanel.swift`

**Why a coordinator:**  
`ContentView` needs to know a cross-panel drag is in progress so it can show the dock gap preview. `FolderExpansionView` needs to notify `ContentView` of drag start/move/end events. A lightweight `@Observable` class shared through the SwiftUI environment is the cleanest channel.

**State the coordinator holds:**

```swift
@Observable class DragCoordinator {
    var isDraggingFromFolder: Bool = false
    var sourceShortcut: AppShortcut? = nil
    var sourceFolder: AppFolder? = nil
    var dropIndex: Int? = nil          // live drop target in dock
    var isOverDock: Bool = false
}
```

**Coordinator methods:**

- `beginDrag(shortcut:folder:icon:startPoint:)` — sets state, calls `DragGhostPanel.shared.show(icon:at:)`, installs a local mouse monitor (same `NSEvent.addLocalMonitorForEvents` pattern as the dock's own drag)
- `handleMouseMoved(to screenPoint:, dockPanel: NSPanel, itemCount: Int)` — calls `DragGhostPanel.shared.move(to:)`, computes `dropIndex` and `isOverDock` by hit-testing the dock panel frame and computing the index from X offset
- `endDrag()` — removes monitor, calls `DragGhostPanel.shared.hide()`, resets all state

**ContentView changes:**

- Inject `DragCoordinator` via `@Environment`
- When `coordinator.isDraggingFromFolder == true`, mirror the dock gap display: compute `displayItems` from `coordinator.dropIndex` the same way the reorder drag does
- Show a visual insertion gap (the empty `Color.clear` slot already used for reorder)

**Result:** The dock shows a live insertion gap as the ghost is dragged across it.

---

### Phase 5 — Drop resolution

**Scope:** `ContentView.swift`, `DragCoordinator.swift`

**Drop logic (called by coordinator on `leftMouseUp`):**

```
if isOverDock && dropIndex != nil:
    1. Find source folder in items by sourceFolder.id
    2. Remove sourceShortcut from folder.shortcuts
    3. If folder is now empty → remove folder DockItem entirely
       If folder has exactly 1 shortcut left → keep as folder (simpler; user can merge-drag later)
    4. Insert DockItem.shortcut(sourceShortcut) at dropIndex
       (adjust index if the folder was removed before the drop point)
    5. AppShortcutStore.save(items)
    6. Dismiss FolderExpansionPanel
else:
    Cancel — leave items unchanged, dismiss ghost
```

**Edge cases:**

| Scenario | Behaviour |
|---|---|
| Drop on empty dock area past last item | Insert at end |
| Drop back into the same folder | Cancel (no-op) |
| Drop onto another folder item | Invoke existing `performMerge` path (folder + shortcut already handled) |
| Source folder becomes empty | Remove the folder DockItem entirely |

**Result:** Releasing over the dock commits the move. Releasing elsewhere cancels cleanly.

---

### Phase 6 — Polish and visual feedback

**Scope:** `FolderExpansionView.swift`, `ContentView.swift`, `DragGhostPanel.swift`

1. **Dismiss folder panel on drag start** — as soon as `onItemDragStart` fires, dismiss `FolderExpansionPanel`. The ghost takes over visually. Avoids the awkward state of the folder panel floating while the shortcut is being dragged.

2. **Shake animation** — `DragGhostIcon` has `isShaking` support. Pass `true` once drag is confirmed (after the first `mouseDragged` event beyond a small hysteresis threshold, e.g. 4 pt) so it doesn't shake on a stationary long-press.

3. **Drop highlight** — when `isOverDock == true`, the gap slot in the dock already shows by Phase 3. No additional work needed.

4. **Cancelled drag snap-back** — if the mouse is released off the dock, hide the ghost with a brief fade (0.15s opacity to 0) rather than instant disappearance.

5. **Accessibility / hover label** — `AppShortcutButton` in `FolderExpansionView` already shows app labels. No changes needed here.

---

## Files Changed

| File | Phase | Change |
|---|---|---|
| `FolderExpansionView.swift` | 1 | Add `onItemDragStart` callback, wire `AppShortcutButton.onDragStart` |
| `FolderExpansionPanel.swift` | 1 | Pass `onItemDragStart` through `show(...)` |
| `DragGhostPanel.swift` | 2 | New — screen-level floating ghost panel |
| `ContentView.swift` | 3 | Migrate dock ghost to `DragGhostPanel`; remove `draggingIcon`, `isShaking` state; remove `DragGhostIcon` from ZStack |
| `DragCoordinator.swift` | 4 | New — `@Observable` shared drag state + mouse monitor |
| `ContentView.swift` | 4–5 | Inject coordinator, react to `isDraggingFromFolder` for gap display, implement drop resolution |
| `DeskMatApp.swift` (or app entry) | 4 | Inject `DragCoordinator` into environment |

---

## What Stays the Same

- `performMerge` — reused as-is for the "drop onto folder" edge case
- `AppShortcutStore.save` — called identically after mutation
- `DragGhostIcon` SwiftUI view — reused inside `DragGhostPanel`, no changes
- `AppShortcutButton` — no changes; `onDragStart` callback interface is already correct
- Dock drag logic (reorder gap, dwell timer, merge detection) — untouched by Phase 3; only the ghost rendering changes
