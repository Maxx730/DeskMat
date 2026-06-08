# Plan: Network Widget Split Graph

## Goal

Replace the current `NetworkGraphView` (download + upload overlaid on one shared canvas) with two independent side-by-side panel graphs — download on the left, upload on the right — each with its own Y-axis scale.

---

## Current State

`NetworkGraphView` in `SystemWidget.swift` renders both `inHistory` (blue) and `outHistory` (red) on a single `Canvas` sharing a common peak value. This means if download traffic dwarfs upload, the upload line sits nearly flat at the bottom. The two series are visually tangled.

`SystemMonitorService` already provides both `netInHistory` and `netOutHistory` as `[Double]` (KB/s, newest-first, 60-sample capacity). No data layer changes are needed.

---

## Design

```
┌──────────────────────────────────────┐
│  ↓ Download     │  ↑ Upload          │
│  ~~~~~~~~~~~~   │      ~~~           │
│ ~~~~~~~~~~~~~~  │  ~~~~~~~~          │
│ 1.2 MB/s        │  48 KB/s          │
└──────────────────────────────────────┘
      left panel       right panel
    (blue waveform)   (red waveform)
```

- Each panel occupies exactly half the widget width (the widget is 2 cells / ~128 pt wide, so ~64 pt each)
- Each panel has its own independent dynamic peak — upload scale is not crushed by download
- A 1 pt vertical divider separates the panels
- Direction label (↓ / ↑) anchored top-left of each panel
- Live rate (KB/s or MB/s) anchored bottom-left of each panel
- Grid lines scoped to each panel's own coordinate space

---

## Phases

---

### Phase 1 — Extract `NetPanelView`, replace `NetworkGraphView` body

**Scope:** `SystemWidget.swift`

Create a private `NetPanelView` struct that renders a single waveform canvas for one direction:

```swift
private struct NetPanelView: View {
    let history: [Double]   // newest-first, KB/s
    let stroke: Color
    let fill: Color
}
```

Replace the `NetworkGraphView` body with an `HStack(spacing: 0)` containing:
1. `NetPanelView(history: inHistory,  stroke: .blue,  fill: ...)`
2. A `Divider()` styled as 1 pt wide, `white.opacity(0.10)`
3. `NetPanelView(history: outHistory, stroke: .red,   fill: ...)`

Move `drawSeries`, `chartPoints`, `linePath`, and `drawGridLines` from `NetworkGraphView` into `NetPanelView`. Each panel now renders entirely within its own `Canvas` coordinate space — no manual width-halving math needed.

The `minimumPeak` stays per-panel:
```swift
private static let minimumPeak: Double = 128   // KB/s
```

Each panel computes its own peak independently from its own history:
```swift
let peak = max(history.max() ?? 0, Self.minimumPeak)
```

**Grid line density:** Halve `vDivisions` from 13 to 6 per panel (each panel is half the width).

---

### Phase 2 — Per-panel labels

**Scope:** `SystemWidget.swift` — `NetPanelView`

Overlay a `ZStack` on each panel canvas with:
- **Direction indicator** (top-left): `↓` or `↑` as a system symbol or string literal, `caption2` weight, white at 60% opacity
- **Live rate** (bottom-left): formatted as `"1.2 MB/s"` or `"48 KB/s"` — reuse the formatting logic already used in the old `NetRow`/`NetworkView` if it still exists, otherwise inline:
  ```swift
  history.first.map { v in
      v >= 1024 ? String(format: "%.1f MB/s", v / 1024) : "\(Int(v)) KB/s"
  }
  ```

Both labels use `.padding(4)` and `font(.system(size: 8, weight: .semibold, design: .monospaced))` to stay compact within the half-width panel.

---

### Phase 3 — Cleanup

**Scope:** `SystemWidget.swift`

- Delete the now-unused `drawSeries`, `chartPoints`, `linePath`, `drawGridLines` methods from `NetworkGraphView` (they've migrated into `NetPanelView`)
- Delete `NetworkGraphView` itself if its only remaining role is composing the two `NetPanelView`s — fold that composition up into the `case .network:` branch in `SystemWidget` directly, or keep `NetworkGraphView` as a thin shell (whichever reads more clearly)
- Verify the `DockWidget(backgroundColor:)` call for `.network` in `SystemWidget` still passes `Color(hex: "#050a14")` — no change expected

---

## Files Changed

| File | Phase | Change |
|---|---|---|
| `SystemWidget.swift` | 1 | Add `NetPanelView`, replace `NetworkGraphView` body with HStack of two panels |
| `SystemWidget.swift` | 2 | Add direction + rate labels inside `NetPanelView` |
| `SystemWidget.swift` | 3 | Remove dead code from old `NetworkGraphView` |

`SystemMonitorService.swift` — **no changes needed**, data layer is already complete.

---

## What Stays the Same

- `SystemMonitorService.netInHistory` / `netOutHistory` — unchanged
- `minimumPeak = 128 KB/s` — carried forward per panel
- Background color (`#050a14`) — unchanged
- CPU and RAM widgets — completely unaffected
- The `clipShape(RAMChipShape(...))` call — unchanged

---

## Key Decision: Independent vs Shared Peak

The old plan used a single shared peak across both series. This plan switches to per-panel independent peaks. Rationale: upload is typically 5–20× lower than download; a shared peak makes upload traffic nearly invisible. Independent peaks let each panel use its full vertical range, making both directions readable at a glance. The tradeoff is you can't visually compare absolute magnitudes — the labels provide that context instead.
