# Plan: CPU Waveform Graph

## Goal

Replace the `HalfCircleMeter` in `CPUView` with a rolling sparkline-style waveform graph that shows recent CPU history on a dot-grid background, matching the provided mockup. The gauge is a single point-in-time reading; the graph gives the user temporal context at a glance.

---

## Target Design (from mockup)

- **Background:** dark panel with a faint dot grid (evenly spaced small circles)
- **Waveform:** smooth filled curve (cubic bezier) drawn in bright green
- **Fill:** gradient from green at the curve peak down to transparent at the baseline
- **Curve line:** solid bright green stroke at the top edge of the fill
- No axis labels, no tick marks — purely visual

---

## Current State

- `CPUView` renders a header label → `HalfCircleMeter` → percent text
- `SystemMonitorService.cpuPercent` exposes only the latest single sample (0–1)
- No history buffer exists anywhere in the service

---

## Phases

---

### Phase 1 — Add CPU history buffer to `SystemMonitorService`

**Scope:** `SystemMonitorService.swift`

Add a fixed-size ring buffer of recent CPU readings so the graph has data to plot.

**Changes:**

```swift
// New published property
var cpuHistory: [Double] = []               // newest sample at index 0

// Constants (private)
private let historyCapacity = 30            // ~30 seconds at 1 Hz
```

At the end of `updateCPU()`, after writing `cpuPercent`, prepend the new sample and trim to capacity:

```swift
cpuHistory.insert(cpuPercent, at: 0)
if cpuHistory.count > historyCapacity { cpuHistory.removeLast() }
```

**Result:** `monitor.cpuHistory` is a `[Double]` with up to 30 entries, index 0 = most recent. The existing `cpuPercent` property is unchanged so `RAMView` and any other consumers are unaffected.

---

### Phase 2 — Build `CPUGraphView` Canvas component

**Scope:** `SystemWidget.swift` (new private struct)

A self-contained `Canvas`-based view that accepts the history array and renders the waveform.

**Signature:**

```swift
private struct CPUGraphView: View {
    let history: [Double]   // newest-first, 0.0–1.0, up to 30 entries
}
```

**Render logic (inside `Canvas`):**

1. **Dot grid background**
   - Draw a grid of small filled circles (radius ~1 pt, spacing ~6×6 pt)
   - Color: `white.opacity(0.08)` — barely visible, gives the graph a retro terminal feel

2. **Waveform path**
   - Map each sample to an x position: `x = width - (i / max(history.count-1, 1)) * width` (index 0 at right edge, oldest at left)
   - Map each value to a y position: `y = height - value * height` (0 = bottom, 1 = top)
   - Build a smooth `Path` using `addCurve` with control points computed as the midpoints between adjacent data points (Catmull-Rom → cubic bezier conversion)
   - Close the path down to the bottom-left and bottom-right corners to form a filled shape

3. **Fill**
   - Stroke the closed path with a `LinearGradient` from `green.opacity(0.55)` at y=0 to `green.opacity(0.0)` at y=height
   - Use `.fill` not `.stroke` for the body

4. **Top line**
   - Re-stroke just the curve (open path, not closed) with solid `Color(red: 0.2, green: 1.0, blue: 0.3, opacity: 0.9)` at `lineWidth: 1.5`, `lineCap: .round`, `lineJoin: .round`

5. **No data state**
   - If `history.isEmpty`, draw nothing (the background grid still shows)

**Animation:** The history array changes every second. SwiftUI re-renders the Canvas automatically. No `Animatable` conformance is needed — the 1 Hz update rate is the natural frame rate for this view.

**Sizing:** The view fills whatever frame the caller provides. No intrinsic size — let `CPUView` constrain it.

---

### Phase 3 — Replace `CPUView` layout

**Scope:** `CPUView` in `SystemWidget.swift`

Swap `HalfCircleMeter` for `CPUGraphView` and adjust the layout to make use of the full cell area.

**New layout:**

```
┌─────────────────────────────┐
│  CPU          23%           │  ← header row (label left, percent right)
│                             │
│   [dot-grid waveform graph] │  ← fills remaining height
│                             │
└─────────────────────────────┘
```

- Replace the `VStack` with a `ZStack` or `VStack` where the graph expands to fill remaining space using `.frame(maxHeight: .infinity)`
- Header row: `HStack` with `Text("CPU")` on the left and `Text("23%")` on the right, both `font(.system(size: 10, weight: .semibold))`, `foregroundStyle(.white.opacity(0.6))`
- The graph takes the remaining height (roughly 45–50 pt in a 64 pt cell)

**Update `CPUView` props:**

```swift
private struct CPUView: View {
    let percent: Double
    let history: [Double]
    ...
}
```

Update the call site in `SystemWidget.body`:

```swift
case .cpu: CPUView(percent: monitor.cpuPercent, history: monitor.cpuHistory)
```

**Remove `HalfCircleMeter`:** Once `CPUView` no longer references it, delete the struct. `RAMView` and `NetworkView` still use it — do NOT delete it until Phase 4.

---

### Phase 4 — Decide fate of `HalfCircleMeter` (RAM + Network)

**Scope:** design decision, then `RAMView` / `NetworkView` if applicable

After the CPU graph ships, evaluate whether RAM and Network should also get graph-style views or keep the arc meters. This phase is held until the CPU graph is validated in production.

Options:
- **Keep arc meters** for RAM (RAM is less bursty; a gauge communicates headroom clearly)
- **Graph for network** (network is highly bursty; a sparkline shows spikes better than a gauge)

When a decision is made, create a follow-on plan.

---

## Files Changed

| File | Phase | Change |
|---|---|---|
| `SystemMonitorService.swift` | 1 | Add `cpuHistory: [Double]`, populate in `updateCPU()` |
| `SystemWidget.swift` | 2 | Add `CPUGraphView` struct |
| `SystemWidget.swift` | 3 | Rewrite `CPUView` layout, remove `HalfCircleMeter` reference from CPU only |

---

## What Stays the Same

- `SystemMonitorService.cpuPercent` — unchanged, still used for the header label
- `RAMView` / `NetworkView` / `HalfCircleMeter` — untouched until Phase 4 decision
- `DockWidget`, `SystemMetric`, `Strings` — no changes
- Widget sizing / cell count — no changes
- All existing unit tests — no behavioral change to non-CPU paths

---

## Open Questions

1. **History length:** 30 samples (30 s) is a reasonable default. Could be user-configurable later via `@AppStorage("cpuHistoryLength")` — leave as a `private let` constant for now.
2. **Smoothing:** Catmull-Rom gives a visually smooth curve. If it looks too wiggly under heavy CPU variance, fall back to a simple linear polygon — the dot grid will soften it.
3. **Color theming:** Green is taken from the mockup. If the app gains a color theme system in the future, wire the graph color through it.
