# Glow Shader — Implementation Plan

Port the abstract glow shader to Metal and wire it into the Reactive background
system as a selectable style named **Glow**.

---

## What the shader does

An abstract, time-driven colour field built from two distorted UV coordinate sets.
The primary UV is warped by a compound `cos(sin(t) + uv.x) * sin(cos(t) + uv)`
oscillation then divided by its own x component, producing a hyperbolic/radial
perspective distortion. A bell-curve falloff (`cos(atan(y))`) along the warped y
axis forms the base intensity `d`. The original undistorted UV scaled by `sin(t)`
gives a radial pulse `e`. These are combined with time-varying divisors to drive
the R, G, and B channels independently, producing slowly shifting neon-toned
colour bands that breathe and flow over time.

---

## Shader walkthrough

```glsl
// Two UV sets — both centred and aspect-corrected
uv  = (fragCoord*2 - resolution) / resolution.y   // distorted copy
uv1 = (fragCoord*2 - resolution) / resolution.y   // original (for e)

// Compound oscillation warp — drives flowing motion
uv += cos(sin(t) + uv.x) * sin(cos(t) + uv);

// Hyperbolic divide — collapses space toward vertical axis
uv /= uv.x;

// d — bell-curve intensity along warped y axis
// cos(atan(y)) = 1/sqrt(1+y²), a smooth peak at y=0
d = length(cos(atan(uv.y * 10.)));   // scalar abs in disguise

// e — radial pulse from original UV, breathing with sin(t)
e = length(uv1 * sin(t));

// Per-channel colour with independent time-based divisors
r = e*d / abs(sin(t));    // breathes fast — near-zero sin causes bright flashes
g = e*d / abs(cos(1.));   // constant divisor ~0.54 — stable green tint
b = d    * abs(atan(t)+1.); // slowly grows as atan(t) approaches π/2
```

---

## Dock adaptation notes

| Concern | Decision |
|---|---|
| Y-axis flip | Apply standard flip: `fragCoord = float2(in.uv.x, 1.0 - in.uv.y) * resolution` |
| `uv /= uv.x` | Division by zero when `uv.x ≈ 0`. Guard: `uv /= (abs(uv.x) > 0.0001 ? uv.x : 0.0001)` |
| `r /= abs(sin(t))` | Near-zero when `t ≈ nπ` — causes extreme brightness spikes. Guard: `max(abs(sin(u.time)), 0.001)` |
| `length(float)` | GLSL `length(scalar)` = `abs(scalar)`. MSL `length()` requires a vector — replace with `abs()` |
| `atan(float)` | Single-argument `atan` is the same in both GLSL and MSL |
| Colors > 1.0 | Intentional — values exceeding 1.0 blow out to white, creating the glow. No clamping. |
| Alpha | Output `float4(col, 1.0)`; `cornerMaskFragment` handles rounded corners |
| CRT passes | Not needed — `useCRT` stays false for `.glow` |

---

## GLSL → MSL translation table

| GLSL | MSL |
|---|---|
| `iTime` | `u.time` |
| `iResolution.xy` | `u.resolution` |
| `fragCoord` (y=0 bottom) | `float2(in.uv.x, 1.0 - in.uv.y) * u.resolution` |
| `vec2` / `vec3` / `vec4` | `float2` / `float3` / `float4` |
| `length(float)` | `abs(float)` |
| `atan(x)` | `atan(x)` |
| `cos(float)` / `sin(float2)` | `cos(float)` / `sin(float2)` (component-wise, same in MSL) |
| `uv /= uv.x` | `uv /= (abs(uv.x) > 0.0001 ? uv.x : 0.0001)` |
| `abs(sin(iTime))` divisor | `max(abs(sin(u.time)), 0.001)` |

---

## Phase 1 — Add `glow` case to `ReactiveStyle`

**File:** `DeskMat/AppEnums.swift`

```swift
enum ReactiveStyle: String, CaseIterable {
    case none       = "None"
    case lockOn     = "Lock-On"
    case liquidFill = "Liquid Fill"
    case rainbow    = "Rainbow"
    case dvd        = "DVD"
    case eighties   = "80s"
    case voronoi    = "Voronoi"
    case subpixel   = "Subpixel"
    case joker      = "Joker"
    case glow       = "Glow"
}
```

**Acceptance criteria:**
- `"Glow"` appears in the Reactive Style dropdown.
- No rendering change yet.

---

## Phase 2 — Route `fragmentShaderName`

**File:** `DeskMat/ReactiveBackgroundView.swift`

```swift
case .glow: return "glowFragment"
```

**Acceptance criteria:**
- Switching to Glow calls `rebuildPipeline()` with `"glowFragment"`.
- Dock renders nothing (pipeline miss) until Phase 3.

---

## Phase 3 — Write `glowFragment` in Metal

**File:** `DeskMat/ReactiveShaders.metal`

Append after `jokerFragment`.

```metal
// MARK: - Glow

fragment float4 glowFragment(VertexOut in [[stage_in]],
                              constant Uniforms& u [[buffer(0)]]) {
    float2 resolution = u.resolution;
    float2 fragCoord  = float2(in.uv.x, 1.0 - in.uv.y) * resolution;

    float2 uv  = (fragCoord * 2.0 - resolution) / resolution.y;
    float2 uv1 = (fragCoord * 2.0 - resolution) / resolution.y;

    // Compound oscillation warp
    uv += cos(sin(u.time) + uv.x) * sin(cos(u.time) + uv);

    // Hyperbolic divide — guard against uv.x ≈ 0
    uv /= (abs(uv.x) > 0.0001 ? uv.x : 0.0001);

    // Bell-curve intensity along warped y — cos(atan(y)) = 1/sqrt(1+y²)
    float d = abs(cos(atan(uv.y * 10.0)));

    // Radial pulse from original UV
    float e = length(uv1 * sin(u.time));

    // Per-channel colour
    float r = e * d / max(abs(sin(u.time)), 0.001);
    float g = e * d / abs(cos(1.0));
    float b = d * abs(atan(u.time) + 1.0);

    float3 col = float3(r, g, b);

    return float4(col, 1.0);
}
```

**Acceptance criteria:**
- Selecting Glow shows shifting neon colour bands across the dock.
- Colors breathe and flow continuously over time.
- No division-by-zero crashes or NaN artefacts.
- Dock corners are masked by the corner mask pass.
- All other styles still work correctly.

---

## Phase 4 — Polish (optional / post-ship)

| Idea | Notes |
|---|---|
| Clamp output | Add `clamp(col, 0.0, 1.0)` or `min(col, 2.0)` to tame extreme brightness spikes on `r` |
| Speed | Multiply `u.time` by a configurable factor to slow or speed the oscillation |
| Hover response | Scale `e` or `d` by `u.indicatorOpacity` for a brightness surge on hover |
| Colour balance | Adjust the `10.0` y-scale in `atan(uv.y * 10.)` to widen or narrow the central bright band |

---

## Out of scope

- Per-channel colour customisation.
- Rendering outside the dock's rounded-rect bounds.
