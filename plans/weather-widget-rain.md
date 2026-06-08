# Plan: Weather Widget Rain Effect

## Goal

Add a rain effect to the weather widget using a Canvas view with a pre-computed static particle array. Drops are short diagonal strokes that fall continuously, wrapping from bottom back to top. Intensity scales with the WMO weather code — light drizzle shows a sparse slow shower, heavy rain/thunder shows a dense fast downpour.

---

## Design

Each raindrop is a short angled line drawn with `.round` lineCap:

```
 \  ← drop (diagonal stroke, angle ~15° from vertical)
  \
```

- Falls vertically with a slight rightward lean (angle offset ~3 pt horizontal per 8 pt vertical)
- Y position wraps: when a drop exits the bottom it re-enters at the top
- X is fixed per drop — the lean gives the impression of wind without moving X

---

## Particle Definition

```swift
private struct Drop {
    let x:       CGFloat   // fixed horizontal position, 0–width
    let speed:   CGFloat   // pixels per second
    let length:  CGFloat   // stroke length in points
    let opacity: Double    // 0–1
    let phase:   CGFloat   // initial Y offset so drops are staggered at launch
}
```

All fields are computed once at struct init from a seeded LCG (same approach as `StarsView`). No per-frame allocation.

---

## Geometry

Widget panel: **128 × 64 pt**

Angle: drop drawn from `(x, y)` to `(x + 2, y + length)` — 2pt horizontal offset per `length` vertical gives a subtle lean without looking exaggerated at small scale.

Y position per frame:
```swift
let y = (elapsed * drop.speed + drop.phase).truncatingRemainder(dividingBy: size.height + drop.length)
```
Adding `drop.length` to the modulus ensures the full stroke exits the bottom before wrapping, preventing a partial stroke pop at the seam.

---

## Intensity Levels

Map WMO code to an intensity level that controls particle count and speed range:

| Level | Codes | Count | Speed range (pt/s) | Length range |
|---|---|---|---|---|
| 0 — none | 0–3, fog, snow | 0 | — | — |
| 1 — drizzle | 51, 53, 55 | 25 | 60–90 | 4–6 |
| 2 — light rain | 56, 57, 61, 63 | 40 | 80–120 | 5–8 |
| 3 — heavy rain | 65, 66, 67, 80, 81, 82 | 60 | 110–160 | 6–10 |
| 4 — storm | 95, 96, 99 | 80 | 140–200 | 7–12 |

Opacity range: `0.25–0.70` regardless of intensity — rain is semi-transparent so the sky shows through.

---

## `RainView` Structure

```swift
struct RainView: View {
    let weatherCode: Int
    let date: Date

    private let drops: [Drop]

    init(weatherCode: Int, date: Date) {
        self.weatherCode = weatherCode
        self.date = date
        self.drops = RainView.makeDrops(for: weatherCode)
    }

    var body: some View {
        Canvas { context, size in
            guard !drops.isEmpty else { return }
            let elapsed = CGFloat(date.timeIntervalSinceReferenceDate)
            for drop in drops {
                let y = (elapsed * drop.speed + drop.phase)
                    .truncatingRemainder(dividingBy: size.height + drop.length)
                var path = Path()
                path.move(to:    CGPoint(x: drop.x,     y: y))
                path.addLine(to: CGPoint(x: drop.x + 2, y: y + drop.length))
                context.stroke(path,
                               with: .color(.white.opacity(drop.opacity)),
                               style: StrokeStyle(lineWidth: 1, lineCap: .round))
            }
        }
        .allowsHitTesting(false)
    }

    private static func makeDrops(for code: Int) -> [Drop] { ... }
}
```

`makeDrops` uses a seeded LCG to generate the particle array for the given intensity level. The seed includes the intensity level so different rain intensities produce different (but stable) drop layouts.

---

## ZStack Placement

Rain sits above clouds and celestial objects — it's the frontmost atmospheric layer — but below the temperature text:

```
1. SkyGradient background
2. StarsView
3. CloudsView (background)
4. CelestialDialView
5. CloudsView (foreground)   ← if re-introduced
6. RainView                  ← new layer
7. Weather content (temp)
```

Note: since rain falls in front of clouds visually, it goes above all `CloudsView` instances.

---

## Phases

---

### Phase 1 — `RainView` with intensity mapping

**Scope:** New file `RainView.swift`

- Define `Drop` struct
- Implement `makeDrops(for:)` with intensity-to-count/speed/length mapping
- Implement `Canvas` body with Y-wrap position math
- No widget integration yet

**Verification:** Temporarily hardcode `weatherCode = 65` to preview heavy rain in a SwiftUI preview or by wiring it up locally.

---

### Phase 2 — Wire into `WeatherWidget`

**Scope:** `WeatherWidget.swift`

- Add `RainView(weatherCode: weatherService.weatherCode, date: timeline.date)` to the ZStack above `CloudsView`
- `RainView` self-gates via `makeDrops` returning an empty array for non-rain codes, so no conditional needed at the call site

---

## Files Changed

| File | Phase | Change |
|---|---|---|
| `RainView.swift` | 1 | New file — particle array, Canvas renderer |
| `WeatherWidget.swift` | 2 | Add `RainView` to ZStack |

---

## What Stays the Same

- `CloudsView` — unmodified; clouds still visible through semi-transparent rain
- `CelestialDialView` — unmodified; sun/moon visible through light rain
- `SkyGradient` — unmodified
- `WeatherService` — unmodified

---

## Open Questions

1. **Color:** Pure white drops are the default. A slight blue tint (`Color(red: 0.7, green: 0.85, blue: 1.0)`) might look more natural — decide after seeing it rendered.
2. **Snow:** Snow codes (71–77) currently excluded. A future plan could add a `SnowView` with slow-drifting large dots using the same pre-computed array pattern.
3. **Wind lean:** The fixed 2pt horizontal offset gives a constant wind direction. Could vary by weather code (storm = more lean) as a future polish pass.
