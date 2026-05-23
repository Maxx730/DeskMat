# 80s Grid Shader — Implementation Plan

Port the Shadertoy retro perspective grid shader to Metal and wire it into the
Reactive background system as a selectable style named **80s**.

---

## What the shader does

A perspective-projected grid scrolls continuously toward the viewer — classic
synthwave / Tron aesthetic. Three slightly offset copies of the grid are
coloured blue, red, and green and composited together, producing chromatic
aberration fringing on every line. A vertical fade (`C`) dims the grid toward
the horizon (top) and brightens it toward the viewer (bottom). Glowing lines
are produced by dividing a small constant by the square-root of the distance
to each grid axis, giving a soft inverse-square falloff.

---

## Shader walkthrough

```glsl
float C = (1. - pow(U.y/R.y, 3.));   // vertical fade: 1 at bottom, 0 at top
U = 5. * (U+U-R) / R.y;              // centre + normalise coords
U.y = 1. - U.y*2.;                    // flip vertical
U /= 1. + U.y/8.;                     // perspective divide
U.y -= iTime;                          // scroll forward over time
```

Three UV copies with small chroma offsets (`C/15`, `C/30`) produce the RGB
fringing. Each copy is turned into a glowing grid via `gVal*C / sqrt(abs(fract(U) - 0.5))`.
The three layers are blended with blue, red, and green weights and multiplied
by `C` again for the fade. A final `O *= 1.5*O` quadratic brighten adds punch.

---

## Dock adaptation notes

| Concern | Decision |
|---|---|
| Y-axis | Shadertoy y=0 at bottom; flip before computing `C` and normalised coords: `fc.y = u.resolution.y − pixelPos.y` |
| Background | The grid fills the entire surface (no transparent background). Apply `roundedRectAlpha` for corner masking; use the computed RGB as the colour output |
| Alpha | Original `vec4` outputs have `w = 0`; replace with `roundedRectAlpha(uv, u.resolution, u.cornerRadius)` |
| Scroll | `U.y -= u.time` directly replaces `iTime` |
| Perspective | `U /= 1. + U.y/8.` works well for the dock's wide/short aspect; tune the `8.` divisor in Phase 4 if needed |
| `C` fade | Keeps the same meaning — bright at the bottom (near horizon) fading to dark at top — which suits the dock's horizontal layout |

---

## GLSL → MSL translation table

| GLSL | MSL |
|---|---|
| `iTime` | `u.time` |
| `iResolution.xy` | `u.resolution` |
| `fragCoord` (y=0 bottom) | `float2(pixelPos.x, u.resolution.y - pixelPos.y)` |
| `vec2` / `vec4` | `float2` / `float4` |
| `fract(x)` | `fract(x)` |
| `abs(x)` | `abs(x)` |
| `sqrt(x)` | `sqrt(x)` |
| `pow(x, n)` | `pow(x, n)` |
| `clamp(x, a, b)` | `clamp(x, a, b)` |
| `void mainImage(out vec4 O, vec2 U)` | `fragment float4 eightiesFragment(...)` |
| `O = vec4(r, g, b, 0)` | build `float3` colour; apply alpha separately |

---

## Phase 1 — Add `eighties` case to `ReactiveStyle`

**File:** `DeskMat/AppEnums.swift`

```swift
enum ReactiveStyle: String, CaseIterable {
    case lockOn     = "Lock-On"
    case liquidFill = "Liquid Fill"
    case rainbow    = "Rainbow"
    case dvd        = "DVD"
    case eighties   = "80s"
}
```

**Acceptance criteria:**
- `"80s"` appears in the Reactive Style dropdown.
- No rendering change yet.

---

## Phase 2 — Route `fragmentShaderName`

**File:** `DeskMat/ReactiveBackgroundView.swift`

```swift
var fragmentShaderName: String {
    switch reactiveStyle {
    case .lockOn:     return "lockOnFragment"
    case .liquidFill: return "liquidFillFragment"
    case .rainbow:    return "rainbowFragment"
    case .dvd:        return "dvdFragment"
    case .eighties:   return "eightiesFragment"
    }
}
```

**Acceptance criteria:**
- Switching to 80s calls `rebuildPipeline()` with `"eightiesFragment"`.
- Dock renders nothing (pipeline miss) until Phase 3.

---

## Phase 3 — Write `eightiesFragment` in Metal

**File:** `DeskMat/ReactiveShaders.metal`

Append after `dvdFragment`.

```metal
// MARK: - 80s Grid
// Adapted from Shadertoy retro perspective grid shader.

fragment float4 eightiesFragment(VertexOut in [[stage_in]],
                                  constant Uniforms& u [[buffer(0)]]) {
    float2 uv       = in.uv;
    float2 pixelPos = uv * u.resolution;
    float2 R        = u.resolution;

    // Flip y to match Shadertoy convention (y=0 at bottom)
    float2 fc = float2(pixelPos.x, R.y - pixelPos.y);

    // Vertical fade: 1 at bottom (near viewer), 0 at top (horizon)
    float C = 1.0 - pow(fc.y / R.y, 3.0);

    // Centre and normalise coordinates
    float2 U = 5.0 * (fc + fc - R) / R.y;

    // Flip vertical and apply perspective
    U.y = 1.0 - U.y * 2.0;
    U  /= 1.0 + U.y / 8.0;

    // Scroll forward over time
    U.y -= u.time;

    // Three chroma-offset copies
    float2 UA = U + C / 15.0;
    float2 UB = U + C / 30.0;

    // Distance to nearest grid axis (creates the grid pattern)
    U  = abs(fract(U)  - 0.5);
    UA = abs(fract(UA) - 0.5);
    UB = abs(fract(UB) - 0.5);

    // Glow: inverse-sqrt falloff from each axis
    float gVal = 0.1;
    U  = gVal * C / sqrt(U);
    UA = gVal * C / sqrt(UA);
    UB = gVal * C / sqrt(UB);

    // Combine layers with blue / red / green weights
    float4 O = (U.x  + U.y)  * float4(0.0, 0.0, 0.8, 0.0)
             +                  float4(0.22, 0.20, 0.20, 0.0)
             + (UA.x + UA.y) * float4(0.8, 0.0, 0.0, 0.0)
             + (UB.x + UB.y) * float4(0.0, 0.7, 0.0, 0.0);

    O *= C;
    O  = clamp(O, 0.0, pow(C, 1.8));
    O *= 1.5 * O;

    float alpha = roundedRectAlpha(uv, u.resolution, u.cornerRadius);
    return float4(O.rgb, alpha);
}
```

**Acceptance criteria:**
- Selecting 80s shows a scrolling perspective grid with blue/red/green chromatic
  fringing across the dock.
- The grid scrolls continuously toward the viewer.
- Brightness fades toward the top of the dock (horizon).
- Dock corners are correctly masked.
- All other styles still work correctly.

---

## Phase 4 — Polish (optional / post-ship)

| Idea | Notes |
|---|---|
| Perspective strength | Expose the `8.0` divisor in `U /= 1. + U.y/8.` as a uniform for tuning |
| Scroll speed | Multiply `u.time` by a configurable speed factor |
| Colour customisation | Replace hardcoded blue/red/green weights with user-selectable palette |
| Hover pulse | Boost `gVal` on hover using `u.indicatorOpacity` for a brightness swell |
| Grid density | Multiply `U` before `fract` to increase/decrease line frequency |

---

## Out of scope

- True 3D geometry or depth buffer.
- Rendering outside the dock's rounded-rect bounds.
- Interaction with the system Dock or other windows.
