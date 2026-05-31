# Plan: Fix Drag Detection Near Left Edge

## Root cause

`computeDragMode` checks two things in sequence:

1. **Merge check** — iterates remaining items, computes each center as `32 + i * 72` (packed left, no gap)
2. **Reorder check** — computes `rawIndex` (where the gap would be)

The bug: the merge check uses **packed positions** (no gap), but at the time of the check the items are displayed in **reorder positions** (with a gap). These coordinate systems are different.

Concrete example — 4 items [A, B, C, D], dragging A (index 0):

```
Remaining packed (what merge check uses):  B=32  C=104  D=176
Reorder display with gap at index 1:       B=32  GAP=104  C=176  D=248
```

When the cursor is at `localX=104` (visually over the gap), the merge check computes `|104 - 104| < 28.8` and triggers a spurious merge with C — even though C is actually at 176.

Near the left edge this is most severe because the dragged item is typically at a low index (0 or 1), making the gap appear early and shifting many remaining items by a full step (72pt). The further right the cursor moves, the more the packed and reorder positions diverge.

---

## Fix

Compute the reorder `rawIndex` **first**, then use it to derive each remaining item's actual visual center before doing the merge threshold check.

For remaining item at packed index `j`:
- If `j < rawIndex` (item sits before the gap): visual center = `32 + j * step`
- If `j >= rawIndex` (item sits after the gap): visual center = `32 + (j + 1) * step`

Updated `computeDragMode`:

```swift
private func computeDragMode(localX: CGFloat) -> DragMode {
    guard let dragging = draggingItem else { return .reorder(0) }
    let cellSize = DockWidget<EmptyView>.cellSize
    let step = cellSize + hstackItemSpacing
    let mergeThreshold = cellSize * 0.45

    // Compute reorder index first so we know where the gap is
    let rawIndex = Int((localX - cellSize / 2 + step / 2) / step)
    let reorderIndex = max(0, min(items.count - 1, rawIndex))

    // Check merge using gap-adjusted visual centers
    let remaining = items.filter { $0.id != dragging.id }
    for (j, item) in remaining.enumerated() {
        let displayIndex = j < reorderIndex ? j : j + 1
        let centerX = cellSize / 2 + CGFloat(displayIndex) * step
        if abs(localX - centerX) < mergeThreshold {
            return .merge(item.id)
        }
    }

    return .reorder(reorderIndex)
}
```

The merge check now uses the same positions the user sees in reorder mode, so hovering over a gap never triggers a merge, and hovering over an icon body always does — regardless of which icon is being dragged or how far left it started.

---

## Files to change

- `DeskMat/ContentView.swift` — `computeDragMode` only. No other logic changes needed.
