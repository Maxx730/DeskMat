# Worley Shader — Implementation Plan

Port the Worley/cellular noise shader to Metal and wire it into the Reactive background
system as a selectable style named **Worley**.

---

## License

Original shader is unlicensed / public domain. No commercial concerns.

---

## What the shader does

Three octaves of Worley (cellular) noise are composited via nested `sqrt` to produce a
soft web-like glow pattern. Each octave scrolls at a different rate and scale:
- `p * 5.0 + 0.05*t` — large slow cells
- `p * 50.0 - 0.1*t` — fine fast cells
- `p * -10.0 + 0.03*t` — medium cells scrolling opposite direction

The raw Worley value is shaped by `3 * exp(-4 * abs(2.5*d - 1))` — a bell curve that
peaks at d = 0.4, producing a bright ring around each cell centre. A radial gradient
`exp(-length2(abs(0.7*uv - 1.0)))` brightens the upper-right region. The final colour
maps intensity `t` to a blue-teal palette via `vec3(0.1, 1.1*t, pow(t, 0.5-t))`.

---

## Key adaptations

| Concern | Decision |
|---|---|
| `vec2(xo, yo)` with int loop vars | `float2(float(xo), float(yo))` |
| `noise(tp)` subtracted from `vec2` | `float2 - float` broadcasts in MSL — same semantics |
| `iTime` in `fworley` | Pass `u.time` as parameter since helpers can't see uniforms |
| `fragCoord / iResolution` | Use `in.uv` directly (already 0-1, no flip needed — noise is symmetric) |
| Helper naming | `worley_length2`, `worley_noise`, `worley_worley`, `worley_fworley` |
| `pow(t, 0.5-t)` | Valid in MSL — exponent goes negative when t > 0.5 but t > 0 throughout |

---

## GLSL → MSL translation table

| GLSL | MSL |
|---|---|
| `vec2 / vec3 / vec4` | `float2 / float3 / float4` |
| `iTime` | `u.time` (passed as param to `worley_fworley`) |
| `iResolution.xy` | `u.resolution` |
| `fragCoord / iResolution.xy` | `in.uv` |
| `vec2(xo, yo)` (int) | `float2(float(xo), float(yo))` |
| `float2 - float` (noise broadcast) | same — MSL broadcasts scalar arithmetic |

---

## Phase 1 — Add `worley` case to `ReactiveStyle`

**File:** `DeskMat/AppEnums.swift`

```swift
case glitch     = "Glitch"
case worley     = "Worley"
```

---

## Phase 2 — Route `fragmentShaderName`

**File:** `DeskMat/ReactiveBackgroundView.swift`

```swift
case .worley:    return "worleyFragment"
```

---

## Phase 3 — Write `worleyFragment` in Metal

**File:** `DeskMat/ReactiveShaders.metal` — append after `glitchFragment`.

**Acceptance criteria:**
- Selecting Worley shows a glowing cellular web pattern.
- Cells scroll and breathe continuously.
- Colour is blue-teal, brighter in the upper-right region.
- Dock corners are masked by the corner mask pass.
- All other styles still work correctly.

---

## Phase 4 — Polish (optional / post-ship)

| Idea | Notes |
|---|---|
| Colour | Replace `float3(0.1, 1.1*t, pow(t, 0.5-t))` with a configurable palette |
| Speed | Multiply `u.time` by a configurable factor |
| Hover pulse | Scale `t` by `1.0 + u.indicatorOpacity * 0.5` for brightness surge on hover |
| Gradient direction | Adjust `abs(0.7*uv - 1.0)` bias to centre the bright spot |
