# Hover App Label — Implementation Plan

Show the app name as a tooltip above an icon when the user hovers over it. This complements the existing `showLabels` persistent label and gives users who hide labels a way to still identify apps on hover.

---

## Scope

- A small floating label appears above the icon while the cursor is over it.
- It disappears immediately when the cursor leaves.
- The label uses `shortcut.label` (same text as the persistent label below the icon).
- A short appear/disappear animation keeps it feeling polished.
- Works correctly whether `showLabels` is on or off.

---

## Phase 1 — Add hover label state to `AppShortcutButton`

**File:** `DeskMat/AppShortcutButton.swift`

Add a `@State private var showHoverLabel: Bool = false` alongside the existing `isHovering` state.

Set it in the existing `.onHover` handler:
- `true` on enter (only when `!isReordering`)
- `false` on exit

This keeps the label hidden during drag-to-reorder.

---

## Phase 2 — Render the label as an overlay

**File:** `DeskMat/AppShortcutButton.swift`

Add an `.overlay(alignment: .top)` on the icon `ZStack` (the 64×64 frame, above the window-indicator capsule) that renders the label when `showHoverLabel` is true.

Suggested visual:

```swift
if showHoverLabel {
    Text(shortcut.label)
        .font(.caption2)
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
        .offset(y: -44)   // floats above the icon
        .transition(.opacity.combined(with: .scale(scale: 0.85, anchor: .bottom)))
        .zIndex(100)
}
```

Use `withAnimation(.easeInOut(duration: 0.12))` when toggling `showHoverLabel` so the appear/disappear is snappy but not jarring.

The `.zIndex(100)` keeps the label above sibling icons in the `HStack`.

---

## Phase 3 — Prevent clipping at the dock edge

**File:** `DeskMat/ContentView.swift`

The `HStack` inside the `ZStack` clips content to the dock bounds. To let the label float above the dock panel:

- Ensure the outer `ZStack` in `ContentView` has `.clipped(false)` / no implicit clip.
- If clipping is still an issue (SwiftUI clips at window bounds), the label may need to be rendered via a `popover` or an `NSPanel` overlay. Evaluate after Phase 2 — a simple overlay is preferred if it clears the panel edge.

---

## Phase 4 — Settings toggle (optional, post-ship)

Add an `@AppStorage("showHoverLabel") private var showHoverLabel = true` app-wide toggle in `SettingsView` under the Appearance section, guarded the same way as `showLabels`. This lets users who find the tooltip distracting turn it off.

Only implement if requested.

---

## Acceptance criteria

- Hovering an icon shows its name floating above it within ~120 ms.
- Moving away hides the label cleanly.
- Label is not shown during drag-to-reorder.
- Label does not occlude or shift the icon or the persistent label below it.
- Works with `showLabels` both on and off.
- All existing hover animations (`bounce`, `pulse`, `jiggle`, `pop`, `shine`) still work correctly.
