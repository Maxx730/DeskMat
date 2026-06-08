# Plan: System Monitor Half-Circle Analog Meter

## Goal

Replace the horizontal progress bar (`MeterBar`) in the CPU and RAM views of `SystemWidget` with a half-circle analog gauge that reads like a speedometer. The network view already shows raw text values without a bar and will get a pair of small arc meters for in/out bandwidth as an enhancement in Phase 3.

---

## Current State

`SystemWidget.swift` contains:
- `CPUView` — uses `MeterBar` + text label
- `RAMView` — uses `MeterBar` + text label
- `NetworkView` — uses `NetRow` text rows only (no bar)
- `MeterBar` — a flat 4pt-tall `Capsule` progress bar

All drawing is done in SwiftUI layout primitives. The canvas approach (used in `ClockWidget`) is better suited for the arc geometry.

---

## Geometry Reference

`DockWidget` cell size = **64 × 64 pt** (1-cell widget).

For a half-circle meter that fits the cell:
- Center point: bottom-center of the drawing area
- Radius: `dim * 0.42` (leaving room for the stroke width and padding)
- **Start angle**: −180° (9 o'clock / left edge)
- **End angle**: 0° (3 o'clock / right edge)
- Sweep: 180° (flat bottom, arc on top)
- Track stroke width: `dim * 0.07` (background arc, faint)
- Value stroke width: same (filled arc, bright)

The flat baseline of the D-shape sits at the center of the view, leaving the top half for the arc and the bottom half for the numeric label.

---

## Color Scheme

To match the existing widget aesthetic (white-on-dark):

| Value range | Color |
|---|---|
| 0–60% | `white.opacity(0.85)` |
| 60–80% | interpolated toward orange |
| 80–100% | interpolated toward red |

Track (background arc): `white.opacity(0.15)`

The color transition can be implemented as a simple three-stop lerp in the Canvas render function.

---

## Phases

---

### Phase 1 — `HalfCircleMeter` Canvas view

**Scope:** `SystemWidget.swift` (new private struct, no existing code changed)

**Implementation:**

```swift
private struct HalfCircleMeter: View {
    let value: Double   // 0.0 – 1.0

    var body: some View {
        Canvas(renderer: render)
    }

    private func render(context: inout GraphicsContext, size: CGSize) { ... }
}
```

The `render` function draws two arcs using `Path.addArc`:

1. **Track arc** — full 180° from −π to 0, stroked with `white.opacity(0.15)`, `lineCap: .round`
2. **Value arc** — 0 to `value * π` radians swept from the left, stroked with the value-tinted color, same width and cap

Center point = `CGPoint(x: size.width / 2, y: size.height)` (bottom-center, so the arc opens upward).

Animation: the `value` prop changes over time; SwiftUI will interpolate it automatically since `Canvas` re-renders on each `value` change. Add `.animation(.easeOut(duration: 0.4), value: value)` on the Canvas.

**Result:** A reusable `HalfCircleMeter(value:)` view that can be dropped anywhere. No existing code touched.

---

### Phase 2 — Replace `MeterBar` in CPU and RAM views

**Scope:** `CPUView`, `RAMView` in `SystemWidget.swift`

**CPUView layout change:**

```
Before:  [header label] [MeterBar] [percent text]
After:   [HalfCircleMeter (top half of cell)]
         [percent text (inside bottom half)]
```

The `HalfCircleMeter` is sized to fill the available width. The numeric value label sits below the arc's baseline (in the bottom half of the drawing area). Consider overlaying the text directly on the canvas so it sits inside the arc's curve for a gauge-style look, or rendering it just below.

**RAMView layout change:** Same pattern — replace `MeterBar` with `HalfCircleMeter(value: fraction)`. The RAM usage string (`X.X / Y GB`) is placed below.

**Remove `MeterBar`:** Once both callers are migrated, delete the `MeterBar` struct entirely.

**Spacing adjustments:** The meter is taller than the 4pt bar. Remove the `padding(.horizontal, 10)` that was sizing the bar, and let the meter fill the cell naturally. Adjust `VStack(spacing:)` values so header + meter + label all fit within the 64pt cell height.

---

### Phase 3 — Arc meters for Network view (enhancement)

**Scope:** `NetworkView`, `NetRow` in `SystemWidget.swift`

The network widget is 2 cells wide (128 × 64 pt). Currently shows two text rows (↓ in, ↑ out) with no visual meter.

**Enhancement:** Add two small half-circle meters side by side, one for download and one for upload, with the bandwidth text below each. The meter value is the fraction of a soft cap (e.g. 10 MB/s = 100%), clamped to 1.0.

```
[  ↓ arc  ] [  ↑ arc  ]
[ 1.2 MB/s] [ 0.4 MB/s]
```

Each arc gets half the 2-cell width (64pt each), matching the existing cell grid. The soft cap can be a private constant (`let networkCap: Double = 10_000` KB/s) — beyond the cap the meter is full but the text continues to show the real value.

**Result:** The network widget now has the same gauge visual language as CPU/RAM.

---

## Files Changed

| File | Phase | Change |
|---|---|---|
| `SystemWidget.swift` | 1 | Add `HalfCircleMeter` struct |
| `SystemWidget.swift` | 2 | Update `CPUView` + `RAMView` to use `HalfCircleMeter`; delete `MeterBar` |
| `SystemWidget.swift` | 3 | Update `NetworkView` + `NetRow` with arc meters |

All changes are contained in a single file. No other files are affected.

---

## What Stays the Same

- `SystemMonitorService` — data source unchanged
- `DockWidget` wrapper — unchanged
- `SystemMetric` enum and `cellCount` — unchanged
- `Strings.Widgets.SystemMonitor` — all existing strings reused
- The widget's `onAppear`/`onDisappear` lifecycle — unchanged
