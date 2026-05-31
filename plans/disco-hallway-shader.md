# Disco Hallway Shader — Implementation Plan

Port the tunnel LED shader to Metal as a selectable style named **Disco Hallway**.

---

## License

Original shader is unlicensed / public domain. No commercial concerns.

---

## What the shader does

A perspective tunnel of glowing circular LEDs that rush toward the viewer. The tunnel
is rendered in polar coordinates: `r = length(p)` from screen centre, `a = atan2(p.y, p.x)`.
The LED grid lives in `(1/r + time*0.25, a)` space — dividing by r creates the perspective
rush effect. Each LED cell is coloured by a hash of its grid coordinate, animated by a
"sound" pulse. The centre of the tunnel slowly drifts with `sin(time)` oscillations. Color
cycles from dark green to pink/blue over time. The scene is lit more toward the edges (r=1)
and darkens to near-black at the centre.

---

## Texture replacements

| Original texture | Replacement |
|---|---|
| `iChannel1` (noise/LED color) | `disco_hash3(float2)` — returns a pseudo-random float3 per grid cell |
| `iChannel2` (audio) | `pow(0.5 + 0.5 * sin(time * π), 1.5)` — peaks every ~2 seconds |
| `iChannel0` (background) | Dropped — its `* 0.15` weight makes it negligible |

---

## Key adaptations

| Concern | Decision |
|---|---|
| Aspect ratio `uv1.x *= res.x/res.y` | **Removed** — dock is ~19:1; scaling x would push `r` to 19, breaking the color mix |
| `r` near zero | Guard: `r = max(length(p), 0.001)` to avoid `1.0/r` diverging |
| `mod(uv * ntiles, 1.0)` on vec2 | `fmod(uv * ntiles, float2(1.0))` |
| `atan(p.y, p.x)` | `atan2(p.y, p.x)` in MSL |
| `vec3(scalar)` broadcast in `mix` | `float3(scalar)` |
| Final `r * col + (1-r) * back` | Wrapped in `clamp(…, 0.0, 1.0)` — r can exceed 1 at corners |
| Helper naming | `disco_hash3`, `disco_tex` |

---

## Phase 1 — Add `discoHallway` case to `ReactiveStyle`

**File:** `DeskMat/AppEnums.swift`

```swift
case worley       = "Worley"
case discoHallway = "Disco Hallway"
```

---

## Phase 2 — Route `fragmentShaderName`

**File:** `DeskMat/ReactiveBackgroundView.swift`

```swift
case .discoHallway: return "discoHallwayFragment"
```

---

## Phase 3 — Write `discoHallwayFragment` in Metal

**File:** `DeskMat/ReactiveShaders.metal` — append after `worleyFragment`.

**Acceptance criteria:**
- Selecting Disco Hallway shows a perspective LED tunnel rushing toward the viewer.
- LEDs pulse in brightness every ~2 seconds.
- Tunnel centre drifts slowly.
- Color shifts between green and pink/blue over time.
- Dock corners are masked by the corner mask pass.
- All other styles still work correctly.

---

## Phase 4 — Polish (optional / post-ship)

| Idea | Notes |
|---|---|
| Pulse period | Replace `π` multiplier with a configurable rate |
| Hover intensity | Scale `sound` by `1.0 + u.indicatorOpacity * 0.5` |
| LED count | Expose `ntiles = 10.0` as a setting |
| Audio | Wire up real microphone/system audio when AVAudioEngine support is added |
