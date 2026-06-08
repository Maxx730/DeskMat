# Plan: Weather Widget Sky Gradient Background

## Goal

Map the current time of day to a background color on the weather widget, using a multi-stop sky color gradient so the widget reads like a miniature sky — dawn, daylight, sunset, and night are all visually distinct. The color progresses continuously: halfway through the day means halfway through the gradient.

---

## Current State

`WeatherWidget` passes no `backgroundColor` to `DockWidget`, so it renders with the default dark glass look. `DockWidget` already accepts an optional `backgroundColor: Color?` parameter — when provided it bypasses the default dark/stroke styling entirely, so zero changes to `DockWidget` are needed.

---

## Gradient Design

Twelve color stops keyed to hour-of-day (24h clock). Linear interpolation between adjacent stops produces the continuous progression.

| Time | Label | Color (approx) |
|---|---|---|
| 00:00 | Midnight | Deep navy `(0.02, 0.05, 0.18)` |
| 04:00 | Pre-dawn | Dark blue `(0.04, 0.07, 0.22)` |
| 05:30 | First light | Indigo `(0.15, 0.12, 0.40)` |
| 06:30 | Sunrise | Warm orange `(0.80, 0.38, 0.12)` |
| 07:30 | Golden hour end | Soft gold `(0.92, 0.72, 0.35)` |
| 09:00 | Morning | Clear sky blue `(0.30, 0.62, 0.90)` |
| 12:00 | Noon | Bright blue `(0.20, 0.52, 0.95)` |
| 15:00 | Afternoon | Slightly deeper blue `(0.18, 0.48, 0.88)` |
| 17:30 | Pre-sunset | Warm amber `(0.88, 0.55, 0.20)` |
| 18:30 | Sunset | Deep coral `(0.80, 0.28, 0.15)` |
| 19:30 | Dusk | Blue-purple `(0.18, 0.10, 0.38)` |
| 21:00 | Night | Back to deep navy `(0.02, 0.05, 0.18)` |

Stops outside the listed hours interpolate to the nearest neighbors. Midnight wraps — the 21:00 → 24:00 segment blends back to the 00:00 color, which is the same, so it holds steady through the night.

---

## Phases

---

### Phase 1 — `SkyGradient` helper

**Scope:** New file `SkyGradient.swift`

A pure value-type helper with no SwiftUI dependency (just `Color` and `Date`) that the widget calls to get the current sky color.

**Shape:**

```swift
struct SkyGradient {
    static func color(for date: Date) -> Color
}
```

**Implementation:**

1. Extract the fractional hour from `date` using `Calendar.current` components (hour + minute/60 + second/3600), giving a value in `[0, 24)`
2. Define an array of `(hour: Double, color: (r: Double, g: Double, b: Double))` stops, sorted by hour
3. Find the two adjacent stops that bracket the current hour
4. Compute `t = (currentHour - stop[i].hour) / (stop[i+1].hour - stop[i].hour)`
5. Linearly interpolate each RGB channel: `r = stop[i].r + t * (stop[i+1].r - stop[i].r)` etc.
6. Return `Color(red: r, green: g, blue: b)`

Wrapping: if the current hour is past the last stop (e.g. 21:30), the function clamps to the final color (which matches midnight anyway).

**Result:** `SkyGradient.color(for: Date())` returns the correct interpolated `Color` with no side effects.

---

### Phase 2 — Wire into `WeatherWidget`

**Scope:** `WeatherWidget.swift`

Wrap the `DockWidget` in a `TimelineView` so the background color updates every minute without requiring a full weather refresh.

**Change:**

```swift
TimelineView(.periodic(from: .now, by: 60)) { timeline in
    DockWidget(
        cells: 2,
        isLoading: weatherService.isLoading,
        backgroundColor: SkyGradient.color(for: timeline.date),
        onRefresh: { ... }
    ) {
        // existing content unchanged
    }
}
```

`timeline.date` is the scheduled fire date, so the color is always current to within one minute.

**Text contrast:** The existing content uses `.white` and `.white.opacity(0.8)` — these hold up well against both dark (night) and medium (day) backgrounds. If a light sky color at midday makes white text hard to read, add a subtle text shadow or lower the text opacity slightly during daylight hours (a follow-on polish task).

**Content clipping:** Add `.clipShape(RoundedRectangle(cornerRadius: 10))` after the DockWidget call, matching what the CPU widget does, so the colored background clips to the rounded corners.

---

### Phase 3 — Weather condition tinting (optional follow-on)

**Scope:** `SkyGradient.swift` + `WeatherWidget.swift`

Blend a desaturation/grey overlay on top of the sky color based on the weather code from `WeatherService`:

| Condition | Tint |
|---|---|
| Clear (0) | No tint |
| Partly cloudy (1–2) | 10% grey |
| Overcast (3) | 25% grey |
| Fog (45–48) | 30% warm grey |
| Rain/drizzle (51–82) | 35% blue-grey |
| Snow (71–86) | 20% cool white |
| Thunder (95–99) | 20% dark grey |

Implemented as a second static function:

```swift
static func color(for date: Date, weatherCode: Int) -> Color
```

Internally calls the base `color(for:)` then mixes in the condition tint using a weighted RGB blend.

**Why a separate phase:** The base sky gradient already provides strong visual feedback on its own. Condition tinting adds complexity (it requires surfacing `weatherCode` from `WeatherService`) and can be skipped if the gradient alone reads clearly enough.

---

## Files Changed

| File | Phase | Change |
|---|---|---|
| `SkyGradient.swift` | 1 | New file — gradient stops + interpolation logic |
| `WeatherWidget.swift` | 2 | Wrap DockWidget in TimelineView, pass `backgroundColor` |
| `SkyGradient.swift` | 3 | Add weather-code tint overload |
| `WeatherWidget.swift` | 3 | Pass `weatherCode` to `SkyGradient.color` |

---

## What Stays the Same

- `WeatherService` — no changes in Phase 1 or 2
- `DockWidget` — no changes (already supports `backgroundColor`)
- Weather data refresh interval — unchanged (still 15 min)
- All widget content layout — unchanged
