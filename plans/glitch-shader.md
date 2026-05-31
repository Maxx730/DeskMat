# Glitch Shader — Implementation Plan

Port the CRT/phosphor glitch shader to Metal and wire it into the Reactive background
system as a selectable style named **Glitch**.

---

## License

Original shader is unlicensed / public domain. No commercial concerns.

---

## What the shader does

A procedural CRT terminal simulation with layered effects:
- Pincushion lens distortion warps UV toward the edges
- Chromatic aberration samples the signal at ±offset for R/B channels
- A procedural glyph renderer draws animated terminal characters in a 80×36 grid
- Horizontal sync noise and RF interference glitch the signal horizontally
- CRT scanlines, RGB phosphor sub-pixel mask, and a horizontal bloom pass
- Vignette darkens the corners; a subtle screen reflection adds depth
- Film grain and a slight saturation boost finish the image

---

## Key adaptations

| Concern | Decision |
|---|---|
| `#define` constants | Inline as `const float` locals in the relevant function |
| `max(d, 0.0)` on `vec2` | `max(d, float2(0.0))` — MSL requires matching vector type |
| `vec2(scalar)` | `float2(scalar)` — MSL broadcasts scalar to both components |
| `BLOOM_SAMPLES = 12` | Use literal `12` in the loop; denominator `6.0` inlined |
| `fragCoord` for sub-pixel mask | `in.uv.x * u.resolution.x` for raw pixel X |
| Y-axis | Flip: `uv = float2(in.uv.x, 1.0 - in.uv.y)` to match GLSL convention |
| Helper naming | `glitch_gold_noise`, `glitch_curve`, `glitch_sdRect`, `glitch_glyph`, `glitch_getSignal` |
| `fract(time)` | Valid in MSL for scalar float |

---

## GLSL → MSL translation table

| GLSL | MSL |
|---|---|
| `vec2 / vec3 / vec4` | `float2 / float3 / float4` |
| `iTime` | `u.time` |
| `iResolution.xy` | `u.resolution` |
| `fragCoord / iResolution.xy` | `float2(in.uv.x, 1.0 - in.uv.y)` |
| `max(vec2, 0.0)` | `max(float2, float2(0.0))` |
| `#define BLOOM_SAMPLES 12` | literal `12` in loop; `6.0` for denominator |
| `mod(x, 3.0)` | `fmod(x, 3.0)` |

---

## Phase 1 — Add `glitch` case to `ReactiveStyle`

**File:** `DeskMat/AppEnums.swift`

```swift
case starfield  = "Starfield"
case glitch     = "Glitch"
```

---

## Phase 2 — Route `fragmentShaderName`

**File:** `DeskMat/ReactiveBackgroundView.swift`

```swift
case .glitch:    return "glitchFragment"
```

---

## Phase 3 — Write `glitchFragment` in Metal

**File:** `DeskMat/ReactiveShaders.metal` — append after `starfieldFragment`.

See implementation below.

**Acceptance criteria:**
- Selecting Glitch shows animated terminal glyphs with CRT lens distortion.
- Horizontal sync glitches and RF interference fire intermittently.
- Scanlines, phosphor mask, bloom, vignette, and grain all visible.
- Dock corners are masked by the corner mask pass.
- All other styles still work correctly.

---

## Phase 4 — Polish (optional / post-ship)

| Idea | Notes |
|---|---|
| Hover glitch surge | Scale `GLITCH_INTENSITY` by `1.0 + u.indicatorOpacity * 4.0` on hover |
| Phosphor colour | Expose amber vs green blend as a user setting |
| Curvature | Expose `PINCUSHION_DIST` (currently 0.12) for CRT-feel dial |
| Bloom width | `2.2 / resolution.x` controls bloom spread — expose as setting |
