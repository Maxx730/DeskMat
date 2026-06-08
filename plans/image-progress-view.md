# Plan: ImageProgressView

## Goal

A reusable `ImageProgressView` that displays any image as a progress indicator. The "filled" portion renders at full brightness; the "empty" portion is visibly dimmed. Supports horizontal and vertical axes, and fill direction (left→right, right→left, bottom→top, top→bottom).

Immediate use case: RAM widget — the chip image fills left-to-right as RAM usage increases.

---

## Design

```
value = 0.6, axis = .horizontal, reversed = false

┌────────────────────────────┐
│ full brightness │  dimmed  │
│◄──── 60% ──────►◄── 40% ──►│
└────────────────────────────┘
```

---

## Implementation Approach

Two copies of the same image stacked in a `ZStack`:

1. **Bottom layer** — full image, dimmed (reduced brightness + desaturated)
2. **Top layer** — full image, normal brightness, clipped to the filled region

Both layers use identical rendering (`.resizable().scaledToFit()`) so they occupy the same frame and scale identically. The clip on the top layer correctly reveals only the filled portion because both images share the same coordinate space.

```swift
ZStack {
    // Empty state — dimmed full image
    image.resizable().scaledToFit()
         .brightness(dimBrightness)
         .saturation(dimSaturation)

    // Filled state — full brightness, clipped to progress region
    image.resizable().scaledToFit()
         .clipShape(ProgressClipShape(value: value, axis: axis, reversed: reversed))
}
```

---

## `ProgressClipShape`

A `Shape` that returns the filled rectangle based on value, axis, and direction.

```swift
private struct ProgressClipShape: Shape {
    var value: Double     // 0–1, Animatable
    var axis: Axis
    var reversed: Bool

    func path(in rect: CGRect) -> Path {
        let v = max(0, min(1, value))
        let r: CGRect
        switch (axis, reversed) {
        case (.horizontal, false): // left → right
            r = CGRect(x: rect.minX, y: rect.minY,
                       width: rect.width * v, height: rect.height)
        case (.horizontal, true):  // right → left
            r = CGRect(x: rect.maxX - rect.width * v, y: rect.minY,
                       width: rect.width * v, height: rect.height)
        case (.vertical, false):   // bottom → top
            r = CGRect(x: rect.minX, y: rect.maxY - rect.height * v,
                       width: rect.width, height: rect.height * v)
        case (.vertical, true):    // top → bottom
            r = CGRect(x: rect.minX, y: rect.minY,
                       width: rect.width, height: rect.height * v)
        }
        return Path(r)
    }
}
```

`value` conforms to `Animatable` so SwiftUI interpolates it smoothly between updates via `.animation()` at the call site.

---

## `ImageProgressView` API

```swift
struct ImageProgressView: View {
    let image:          Image
    let value:          Double        // 0.0 – 1.0
    var axis:           Axis    = .horizontal
    var reversed:       Bool    = false
    var dimBrightness:  Double  = -0.35   // applied to empty region
    var dimSaturation:  Double  = 0.4     // desaturation of empty region
}
```

### Parameters

| Parameter | Default | Description |
|---|---|---|
| `image` | — | Any `Image` (asset, SF Symbol, etc.) |
| `value` | — | Fill fraction, 0–1 |
| `axis` | `.horizontal` | Fill along x or y axis |
| `reversed` | `false` | Fill from the far edge instead |
| `dimBrightness` | `-0.35` | How much darker the empty region is |
| `dimSaturation` | `0.4` | Colour saturation of empty region (0 = grayscale) |

---

## Phases

---

### Phase 1 — `ImageProgressView` component

**Scope:** New file `ImageProgressView.swift`

- `ProgressClipShape` conforming to `Shape` with `Animatable` value
- `ImageProgressView` with the dual-image ZStack
- No app integration yet

---

### Phase 2 — Wire into `RAMView`

**Scope:** `SystemWidget.swift` — `RAMView.body`

Replace the plain `Image("ram")` with `ImageProgressView`:

```swift
var body: some View {
    ImageProgressView(
        image: Image("ram"),
        value: fraction,
        axis: .horizontal
    )
    .animation(.easeOut(duration: 0.4), value: fraction)
}
```

`fraction` is already computed as `used / total` (0–1) so it maps directly to the progress value.

---

## Files Changed

| File | Phase | Change |
|---|---|---|
| `ImageProgressView.swift` | 1 | New file — shape + view |
| `SystemWidget.swift` | 2 | `RAMView.body` uses `ImageProgressView` |

---

## What Stays the Same

- The `RAMChipShape` clip on the `DockWidget` — unaffected, still cuts the notches
- `SystemMonitorService` — no changes
- All other widgets — unaffected

---

## Open Questions

1. **Dim style:** `brightness + saturation` is the default. Could also use `.opacity()` alone for a simpler fade — test both to see which reads better on the chip image.
2. **Soft edge:** A hard clip edge between bright and dim may look abrupt. A narrow gradient blend (4–8pt feather) could soften the transition — implement as a follow-on if needed.
3. **Fill direction for RAM:** Left→right (default) matches the natural reading direction. If the chip image has a specific visual alignment (e.g. the pins suggest a direction), reverse if needed.
