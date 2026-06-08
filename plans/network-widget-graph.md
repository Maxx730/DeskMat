# Plan: Network Widget Graph

## Goal

Replace the text-only `NetworkView` (up/down KB/s labels) with a dual-line waveform graph — download in blue, upload in red — styled consistently with `CPUGraphView`. The network widget is 2 cells wide (128×64 pt), giving more horizontal space for history than the CPU widget.

---

## Current State

`NetworkView` renders two `NetRow` text rows (↓ in, ↑ out) with no visual graph. `SystemMonitorService` exposes `netInKBs` and `netOutKBs` as single point-in-time values — no history.

`CPUGraphView` (reference implementation):
- Canvas-based waveform with grid lines and filled area under the curve
- History from `cpuHistory: [Double]` (30 samples, newest-first, normalised 0–1)
- Straight-line segments between samples
- Floor offset keeps the baseline off the bottom edge

---

## Design

```
128 × 64 pt panel

↓ download (blue line + fill)
↑ upload   (red line + fill)

Both plotted on the same Y axis, scaled to a shared dynamic peak.
Current values shown as small labels at the right edge.
```

**Y-axis scaling — dynamic shared peak:**

Network traffic is unbounded (0 to many MB/s), unlike CPU (always 0–1). Both histories share a common scale:

```
peak = max(max(inHistory), max(outHistory), minimumPeak)
normalised = value / peak
```

`minimumPeak = 128.0` KB/s — ensures a small-but-real signal is visible at the bottom rather than a flat line. As traffic grows the scale auto-adjusts upward; as old peaks drop off history the scale gradually shrinks.

---

## Phases

---

### Phase 1 — Add network history to `SystemMonitorService`

**Scope:** `SystemMonitorService.swift`

Add two history arrays alongside `cpuHistory`, populated in `updateNetwork()`:

```swift
var netInHistory:  [Double] = []   // newest-first, raw KB/s
var netOutHistory: [Double] = []   // newest-first, raw KB/s

private let netHistoryCapacity = 60  // wider widget → more samples look good
```

At the end of `updateNetwork()`, after writing `netInKBs` / `netOutKBs`:

```swift
netInHistory.insert(netInKBs, at: 0)
if netInHistory.count  > netHistoryCapacity { netInHistory.removeLast() }
netOutHistory.insert(netOutKBs, at: 0)
if netOutHistory.count > netHistoryCapacity { netOutHistory.removeLast() }
```

Raw KB/s is stored (not normalised) so the graph view can compute a shared dynamic scale at render time.

---

### Phase 2 — `NetworkGraphView` Canvas view

**Scope:** `SystemWidget.swift` (new private struct)

A Canvas view that renders both lines on the same coordinate space.

**Signature:**
```swift
private struct NetworkGraphView: View {
    let inHistory:  [Double]   // download, newest-first, KB/s
    let outHistory: [Double]   // upload, newest-first, KB/s
}
```

**Render sequence:**
1. Compute `peak` = `max(inHistory.max() ?? 0, outHistory.max() ?? 0, 128)`
2. Draw grid lines (same helper pattern as `CPUGraphView`)
3. For each history array, map to `[CGPoint]` using `peak` for normalisation and a small floor (`0.05`) to keep a flat zero line off the very bottom
4. Draw filled area under download curve — blue at low opacity
5. Draw download curve stroke — solid blue
6. Draw filled area under upload curve — red at low opacity
7. Draw upload curve stroke — solid red

**Colours:**
- Download (in):  stroke `Color(hex: "#4a9eff")`, fill same at `opacity(0.18)`
- Upload (out):  stroke `Color(hex: "#ff4a4a")`, fill same at `opacity(0.18)`
- Grid lines: `white.opacity(0.08)` (neutral, works on any background)

**Background:** Same dark approach as CPU — `DockWidget(backgroundColor:)` with `Color(hex: "#050a14")` (very dark navy) when `metric == .network`.

**Current value labels:** Small text overlay (top-right corner) showing live KB/s or MB/s for both channels, formatted the same way `NetRow` currently formats them.

---

### Phase 3 — Wire into `SystemWidget`

**Scope:** `SystemWidget.swift`

1. Update `DockWidget(backgroundColor:)` to add the network case:
   ```swift
   metric == .network ? Color(hex: "#050a14") : nil
   ```

2. Replace the `NetworkView` call with `NetworkGraphView`:
   ```swift
   case .network: NetworkGraphView(
       inHistory:  monitor.netInHistory,
       outHistory: monitor.netOutHistory
   )
   ```

3. Update `clipShape` to handle network — `RAMChipShape(showNotches: metric == .ram)` already passes `false` for network so it clips as a plain `RoundedRectangle`. No change needed.

4. Delete `NetworkView` and `NetRow` structs once `NetworkGraphView` is the sole consumer.

---

## Files Changed

| File | Phase | Change |
|---|---|---|
| `SystemMonitorService.swift` | 1 | Add `netInHistory`, `netOutHistory`, populate in `updateNetwork()` |
| `SystemWidget.swift` | 2 | Add `NetworkGraphView` struct |
| `SystemWidget.swift` | 3 | Swap call site, add background color, delete old structs |

---

## What Stays the Same

- `SystemMonitorService.netInKBs` / `netOutKBs` — unchanged, still single-value
- CPU and RAM widgets — completely unaffected
- `CPUGraphView` — not modified; `NetworkGraphView` follows the same pattern independently
- Timer interval — unchanged (0.25 s), giving 60 samples ≈ 15 seconds of history

---

## Open Questions

1. **Label placement:** Current value labels could go top-left (mirroring CPUView), or top-right with arrows. Top-left with a `↓` and `↑` indicator is clean and consistent.
2. **Scale smoothing:** The dynamic peak can jump sharply if a big transfer starts. A smoothed peak (e.g. rolling max decaying over a few samples) could be added as a polish pass.
3. **Zero-traffic appearance:** At zero traffic both lines sit at the floor. This is intentional — a flat line at the bottom correctly communicates no activity.
