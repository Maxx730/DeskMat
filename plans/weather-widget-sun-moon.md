# Plan: Weather Widget Sun & Moon Dial

## Goal

Add a sun and moon that orbit a fixed circle in the weather widget panel, rotating continuously over a 24-hour cycle. The sun is at the top of the circle at noon; the moon is always diametrically opposite (top at midnight). Both are always visible — no fading or visibility logic required. The effect reads like a mechanical watch complication embedded in the weather panel.

---

## Design

```
        ☀  ← noon (top)
       / \
      |   |   ← orbit circle (thin ring)
       \ /
        ☾  ← midnight (bottom, always opposite sun)
```

- The **orbit circle** is a subtle stroked ring centered in the panel
- The **sun** and **moon** are small filled circles riding on the orbit ring
- Both rotate clockwise, completing one full revolution every 24 hours
- At noon the sun is at 12 o'clock; at midnight the moon is at 12 o'clock

---

## Context: Weather Widget ZStack

```
1. SkyGradient background     (DockWidget backgroundColor)
2. StarsView                  (Canvas, night only)
3. ← CelestialDialView here
4. Weather content             (icon + temperature)
```

---

## Geometry

The widget panel is **128 × 64 pt**. The dial is centered in the panel.

- **Orbit radius:** `orbitR = 22 pt` — fits within the 64 pt height with margin
- **Sun radius:** `6 pt`
- **Moon radius:** `5 pt`
- **Orbit ring stroke:** `0.5 pt`, `white.opacity(0.2)` — barely visible guide

**Angle calculation:**

```swift
// hour is fractional (e.g. 13.5 = 1:30 PM)
// Map 24h to full rotation, with noon at top (-π/2 in y-down coords)
let sunAngle  = (hour / 24.0) * .pi * 2 - .pi / 2
let moonAngle = sunAngle + .pi   // always opposite
```

**Position:**

```swift
let sunX  = center.x + orbitR * cos(sunAngle)
let sunY  = center.y + orbitR * sin(sunAngle)
```

At noon (hour = 12): `angle = (12/24)*2π - π/2 = π - π/2 = π/2`... wait, let me be precise:

```
sunAngle at hour=0  (midnight) = (0/24)*2π - π/2 = -π/2  → top
sunAngle at hour=6  (sunrise)  = (6/24)*2π - π/2 =  0    → right
sunAngle at hour=12 (noon)     = (12/24)*2π - π/2 = π/2  → bottom
```

That puts midnight at top and noon at bottom, which is backwards from the natural reading. Reverse the mapping by negating:

```swift
let sunAngle = -((hour / 24.0) * .pi * 2) - .pi / 2
```

Now:
- hour=0  (midnight): angle = -π/2 → **bottom** (sun below horizon ✓)
- hour=6  (sunrise):  angle = -π/2 - π/2 = -π → left
- hour=12 (noon):     angle = -π/2 - π = -3π/2 = π/2 in range → **top** ✓
- hour=18 (sunset):   angle = → right

Moon is always `sunAngle + π`.

---

## Shared Abstraction: `CelestialBody`

Pure value type — position and appearance only.

```swift
struct CelestialBody {
    enum Kind { case sun, moon }
    let kind:     Kind
    let position: CGPoint
    let radius:   CGFloat
}

static func bodies(for date: Date, center: CGPoint, orbitR: CGFloat) -> [CelestialBody]
```

No opacity needed — both bodies are always present.

---

## Drawing: `CelestialDialView`

Canvas view placed in the weather widget ZStack:

```swift
struct CelestialDialView: View {
    let date: Date

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let orbitR: CGFloat = 22

            // Orbit guide ring
            context.stroke(
                Path(ellipseIn: CGRect(x: center.x - orbitR, y: center.y - orbitR,
                                       width: orbitR * 2, height: orbitR * 2)),
                with: .color(.white.opacity(0.2)),
                lineWidth: 0.5
            )

            for body in CelestialBody.bodies(for: date, center: center, orbitR: orbitR) {
                switch body.kind {
                case .sun:  drawSun(&context, body: body)
                case .moon: drawMoon(&context, body: body)
                }
            }
        }
        .allowsHitTesting(false)
    }
}
```

**Sun:** yellow fill + soft glow ring

**Moon:** silver disk with an offset carve disk in the current sky color (`SkyGradient.color(for: date, weatherCode: 0)`) to produce a crescent

---

## Phases

---

### Phase 1 — `CelestialBody` value type

**Scope:** New file `CelestialBody.swift`

- `CelestialBody` struct with `Kind` enum, `position`, `radius`
- `static func bodies(for date: Date, center: CGPoint, orbitR: CGFloat) -> [CelestialBody]`
- Angle math as described above, extracted from `Calendar.current`

---

### Phase 2 — `CelestialDialView` + sun

**Scope:** New file `CelestialDialView.swift`

- `CelestialDialView` Canvas view
- Orbit guide ring draw
- `drawSun` — yellow fill (`Color(red: 1.0, green: 0.85, blue: 0.20)`) + glow ring at `opacity(0.3)`, 3pt wider radius
- Wire into `WeatherWidget.swift`: `CelestialDialView(date: simulatedDate)` in ZStack between `StarsView` and content

---

### Phase 3 — Moon rendering

**Scope:** `CelestialDialView.swift`

- `drawMoon` — silver disk (`Color(white: 0.88)`) + carve disk offset by `radius * 0.4` in sky color
- No widget changes needed — moon already returned by `CelestialBody.bodies`

---

## Files Changed

| File | Phase | Change |
|---|---|---|
| `CelestialBody.swift` | 1 | New — value type + angle math |
| `CelestialDialView.swift` | 2 | New — Canvas view, orbit ring, sun |
| `WeatherWidget.swift` | 2 | Insert `CelestialDialView` into ZStack |
| `CelestialDialView.swift` | 3 | Add moon drawing |

---

## What Stays the Same

- `StarsView` — unmodified; stars visible behind the dial at night
- `SkyGradient` — no changes; moon reuses for crescent carve color
- `WeatherService` — no changes
- Weather content (icon + temperature) — no changes
