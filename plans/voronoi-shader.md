# Voronoi Shader — Implementation Plan

Port the "Voronoi CRT Defrag & Refrag" Shadertoy shader to Metal and wire it
into the Reactive background system as a selectable style named **Voronoi**.

---

## What the shader does

Animated Worley (Voronoi) noise where each cell's seed point orbits on a
Lissajous-like path driven by `sin(time)` and `cos(time)`. The nearest-cell
distance is used to:

- Colour each pixel by the seed point's position (R and G channels)
- Add edge shading via `sin(3 * distance)` bands
- Place bright centre dots at each cell nucleus

A vignette layer (darkens toward edges), contrast adjustment, and high-frequency
scanlines are composited on top. The whole image slowly breathes via a `sin(time)`
zoom on the UV scale.

---

## Shader walkthrough

```glsl
// Three UV variants for different purposes
uv  → pixelated + aspect-corrected → Voronoi input
uv2 → uv *= 1.0 - uv.yx           → vignette (0 at edges, peaks at centre)
uv3 → centred [-1,1] + aspect      → scanline input

// Pixelation snaps UV to 4px grid
uv = (ceil(fragCoord/4 + 0.5) * 4) / resolution;

// Scale oscillates: sin(time)/2 + 6 → range [5.5, 6.5]  (slow breathe)
uv *= sin(time)/2. + 6.;

// Voronoi — 3×3 neighbourhood search
point = 0.5 + (sin(t)/2+0.5) * cos(t + 8.6236*point);  // Lissajous orbit

// Colour
color.xy  += dot(minPoint, vec2(0.25, 0.75));   // hue from cell position
color.x   -= abs(sin(3*minDist)) * 0.25;         // edge banding
color.y   += 1 - step(threshold, minDist);       // centre dot (green)
color.xz  += 0.75 - step(threshold, minDist);    // centre dot (white tint)

// Composite: mix(foreground, background, foreground.a)
```

---

## Dock adaptation notes

| Concern | Decision |
|---|---|
| Y-axis flip | Shadertoy y=0 at bottom; compute `fragCoord = float2(pixelPos.x, resolution.y - pixelPos.y)` before all UV derivations |
| Scanline count | Original `resolution.y * 32` = ~2688 for an 84px dock — far too dense. Reduce to `resolution.y * 4` for ~336 visible bands |
| Vignette | `uv2.x * uv2.y * 10` works in [0,1] space; on the dock's wide aspect ratio the horizontal fade will be subtle — acceptable |
| Alpha | Output `float4(color, 1.0)`; `cornerMaskFragment` handles rounded corners as with all other styles |
| CRT passes | The shader has its own scanlines and vignette — do **not** route through the CRT pipeline (`useCRT` stays false for `.voronoi`). Adding CRT on top would double the scanlines |
| Pixelation | 4px snap on an 84px tall dock gives ~21 rows — this looks like a coarse grid. Can be tuned in Phase 4 |

---

## GLSL → MSL translation table

| GLSL | MSL |
|---|---|
| `iTime` | `u.time` |
| `iResolution.xy` | `u.resolution` |
| `fragCoord` (y=0 bottom) | `float2(pixelPos.x, u.resolution.y - pixelPos.y)` |
| `vec2` / `vec3` / `vec4` | `float2` / `float3` / `float4` |
| `fract(x)` | `fract(x)` |
| `floor(x)` | `floor(x)` |
| `ceil(x)` | `ceil(x)` |
| `step(a, b)` | `step(a, b)` |
| `pow(x, n)` | `pow(x, n)` |
| `abs(x)` | `abs(x)` |
| `length(v)` | `length(v)` |
| `dot(a, b)` | `dot(a, b)` |
| `mix(a, b, t)` | `mix(a, b, t)` |
| `random(float)` | `voronoi_random_f(float)` — rename to avoid collision with `crt_random` |
| `random(vec2)` | `voronoi_random_v2(float2)` — rename, separate overload not allowed in same file |
| `uv2 *= 1.0 - uv2.yx` | `uv2 *= 1.0 - uv2.yx` (MSL swizzle RHS evaluated before assignment — same semantics) |
| `color.xz += val` | `color.xz += val` (MSL supports component-wise swizzle assignment) |

---

## Phase 1 — Add `voronoi` case to `ReactiveStyle`

**File:** `DeskMat/AppEnums.swift`

```swift
enum ReactiveStyle: String, CaseIterable {
    case lockOn     = "Lock-On"
    case liquidFill = "Liquid Fill"
    case rainbow    = "Rainbow"
    case dvd        = "DVD"
    case eighties   = "80s"
    case voronoi    = "Voronoi"
}
```

**Acceptance criteria:**
- `"Voronoi"` appears in the Reactive Style dropdown.
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
    case .voronoi:    return "voronoiFragment"
    }
}
```

**Acceptance criteria:**
- Switching to Voronoi calls `rebuildPipeline()` with `"voronoiFragment"`.
- Dock renders nothing (pipeline miss) until Phase 3.

---

## Phase 3 — Write `voronoiFragment` in Metal

**File:** `DeskMat/ReactiveShaders.metal`

Append after `eightiesFragment`.

### Helpers

```metal
// MARK: - Voronoi CRT Defrag & Refrag

float voronoi_random_f(float x) {
    return fract(tan(x) * 1e3);
}

float2 voronoi_random_v2(float2 uv) {
    return fract(
        float2(
            cos(dot(uv.xy, float2(12.9898, 78.2337))),
            sin(dot(uv.yx, float2(86.2361, 55.5983)))
        ) * 81839.41256
    );
}
```

### Fragment function

```metal
fragment float4 voronoiFragment(VertexOut in [[stage_in]],
                                 constant Uniforms& u [[buffer(0)]]) {
    float2 resolution = u.resolution;

    // Flip y to match Shadertoy convention (y=0 at bottom)
    float2 fragCoord = float2(in.uv.x, 1.0 - in.uv.y) * resolution;

    float2 uv = fragCoord / resolution;

    // Secondary UV for vignette
    float2 uv2 = uv;
    uv2 *= 1.0 - uv2.yx;

    // Tertiary UV for scanlines
    float2 uv3 = uv * 2.0 - 1.0;
    uv3.x *= resolution.x / resolution.y;

    // Pixelation filter — snap to 4px grid
    float pixelation = 4.0;
    uv = (ceil(fragCoord / pixelation + 0.5) * pixelation) / resolution;

    // Centre + aspect ratio correction
    uv = uv * 2.0 - 1.0;
    uv.x *= resolution.x / resolution.y;

    // Slow zoom breathe
    uv *= sin(u.time) / 2.0 + 6.0;

    float2 iuv = floor(uv);
    float2 fuv = fract(uv);

    float  minDist  = 0.6;
    float2 minPoint = float2(0.0);

    for (int i = -1; i <= 1; i++) {
        for (int j = -1; j <= 1; j++) {
            float2 neighbour = float2(float(i), float(j));
            float2 point     = float2(voronoi_random_v2(iuv + neighbour));
            point = 0.5 + (sin(u.time) / 2.0 + 0.5) * cos(u.time + 8.6236 * point);
            float2 diff = neighbour + point - fuv;
            float  dist = length(diff);
            if (dist < minDist) {
                minDist  = dist;
                minPoint = point;
            }
        }
    }

    float3 color = float3(0.0);
    color.xy += dot(minPoint, float2(0.25, 0.75));
    color.x  -= abs(sin(3.0 * minDist)) * 0.25;
    color.y  += 1.0 - step(0.15 - sin(u.time) / 10.0, minDist);
    color.xz += 0.75 - step(0.15 - sin(u.time) / 10.0, minDist);

    float4 background = float4(color, 1.0);

    // Vignette
    float vig = uv2.x * uv2.y * 10.0;
    vig = pow(vig, 0.666);
    float4 foreground = float4(vig);

    // Saturation + contrast
    foreground.xyz -= abs(sin(0.5)) * 0.333;

    // Scanlines — count reduced from 32x to 4x for dock height
    float count = resolution.y * 4.0;
    float2 sl = float2(sin(uv3.y * count), cos(uv3.y * count));
    float3 scanlines = float3(sl.x, sl.y, sl.x);
    foreground = mix(foreground, float4(scanlines, 1.0), foreground.a);

    float4 O = mix(foreground, background, foreground.a);

    return float4(O.rgb, 1.0);  // alpha handled by cornerMaskFragment
}
```

**Acceptance criteria:**
- Selecting Voronoi shows an animated cell pattern with coloured regions and bright centre dots.
- The image slowly breathes (zooms) over time.
- Scanlines are visible.
- Vignette darkens toward the dock edges.
- Dock corners are masked by the corner mask pass.
- All other styles still work correctly.

---

## Phase 4 — Polish (optional / post-ship)

| Idea | Notes |
|---|---|
| Pixelation size | Expose `voronoiPixelation` (1–8) as a uniform; 4px is coarse on an 84px dock — try 2px |
| Scanline density | Tune the `4.0` multiplier or expose as a setting |
| Colour palette | Replace the `vec2(0.25, 0.75)` dot-product weights with configurable hue offset |
| Hover response | Use `u.indicatorOpacity` to boost brightness or contract cell size on hover |
| CRT toggle | Could optionally route through CRT passes for extra grit — would double scanlines; needs a separate toggle |

---

## Out of scope

- True 3D Voronoi / distance field rendering.
- Per-cell colour customisation.
- Rendering outside the dock's rounded-rect bounds.
