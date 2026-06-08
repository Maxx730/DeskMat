# Plan: RAM Widget Chip Background

## Goal

Replace the default `DockWidget` glass background on the RAM widget with the provided RAM chip illustration — a green PCB with gold contact pins, side notches, and a center divider. The existing `HalfCircleMeter` and usage text overlay on top of the image, with colors adjusted for readability against the green background.

---

## Reference Image

The image shows a stylised RAM DIMM module viewed from the connector end:
- **Background:** medium green PCB (`#6aab3f` approx)
- **Pin groups:** two clusters of vertical gold/amber stripes at the bottom
- **Center notch:** white vertical divider between the two pin groups
- **Side notches:** white circles punched into the left and right edges
- **Pin housing:** darker green rounded rectangles behind each pin group

---

## Current State

`RAMView` renders inside the default `DockWidget` (dark glass background):
- `Text` RAM header label
- `HalfCircleMeter` arc gauge
- `Text` usage string (e.g. `8.2 / 16 GB`)
- All text in `.white` / `.white.opacity(0.6)`

`DockWidget` accepts `backgroundColor: Color?` — when provided it replaces the dark glass with a flat fill. For an image background a ZStack inside the content is the right approach (no changes to `DockWidget` needed).

---

## Phases

---

### Phase 1 — Add image asset

**Scope:** `Assets.xcassets`

- Add the RAM chip image to the asset catalog as `ram-chip-bg` (1× PNG, or PDF for vector)
- Name must be `ram-chip-bg` so Phase 2 can reference it via `Image("ram-chip-bg")`

---

### Phase 2 — Wire image into `RAMView`

**Scope:** `SystemWidget.swift` — `RAMView.body`

Wrap the existing content in a `ZStack` with the image as the bottom layer:

```swift
var body: some View {
    ZStack {
        Image("ram-chip-bg")
            .resizable()
            .scaledToFill()
        VStack(spacing: 3) {
            // existing meter + text — colours updated in Phase 3
        }
    }
    .clipShape(RoundedRectangle(cornerRadius: 10))
}
```

Also pass `backgroundColor: Color(hex: "#6aab3f")` to the `DockWidget` in `SystemWidget.body` when `metric == .ram`, so the DockWidget's own background matches the image edge colour and avoids a dark halo if the image doesn't fill flush to the corners.

Update `SystemWidget.body`:
```swift
DockWidget(cells: cellCount,
           backgroundColor: metric == .cpu  ? Color(hex: "#00150a") :
                            metric == .ram  ? Color(hex: "#6aab3f") : nil) {
```

---

### Phase 3 — Readability pass

**Scope:** `SystemWidget.swift` — `RAMView`, `HalfCircleMeter`

The green PCB background is mid-brightness. White text remains readable but the existing `.white.opacity(0.6)` header label becomes too faint. Updates:

| Element | Before | After |
|---|---|---|
| Header label ("RAM") | `.white.opacity(0.6)` | `.white.opacity(0.9)` with `.shadow(radius: 1)` |
| Usage string | `.white` | `.white` with `.shadow(radius: 1)` |
| Meter track (background arc) | `white.opacity(0.15)` | `white.opacity(0.25)` |
| Meter fill | white → orange → red ramp | Keep existing ramp — reads well on green |

A subtle text shadow anchors the labels against the textured background without needing a scrim overlay.

---

## Files Changed

| File | Phase | Change |
|---|---|---|
| `Assets.xcassets/ram-chip-bg.imageset/` | 1 | New image asset |
| `SystemWidget.swift` | 2 | `RAMView.body` — ZStack + image layer; `DockWidget` backgroundColor for ram |
| `SystemWidget.swift` | 3 | Text opacity + shadow; meter track opacity |

---

## What Stays the Same

- `HalfCircleMeter` struct — no structural changes, only minor style values
- `DockWidget` — no changes
- `CPUView` and `NetworkView` — unaffected
- `SystemMonitorService` — unaffected

---

## Open Questions

1. **Image scaling:** `scaledToFill` will crop the image slightly on the short axis. If the crop loses important detail (e.g. the side notches), switch to `scaledToFit` with a matching solid green background behind it.
2. **Corner clipping:** `clipShape(RoundedRectangle(cornerRadius: 10))` on the ZStack clips both image and content. The `DockWidget`'s own corner radius is also 10, so they should align. Verify at runtime.
3. **Dark mode:** The green PCB image is high-contrast and looks intentional in both modes — no dark-mode variant needed unless the image looks out of place.
