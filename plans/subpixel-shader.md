# Subpixel Shader — Implementation Plan

Port the "RGB Subpixels by chronos" Shadertoy shader to Metal and wire it into
the Reactive background system as a selectable style named **Subpixel**.

---

## What the shader does

An animated grid of cells, each randomly lit or dark (binary threshold noise).
Lit cells are subdivided into three vertical columns coloured Red, Green, and
Blue — mimicking physical LCD subpixel layout. Each cell's on/off state flickers
slowly over time via a time-quantised hash. The grid scrolls continuously and
can zoom based on mouse Y position. A cosine envelope shapes each dot's edge for
a soft, rounded look. Gamma correction is applied to the final output.

---

## Shader walkthrough

```glsl
// Hash — maps vec3 seed → [0, 1) float
float hash(vec3 p) { ... }

// Per-cell pattern
vec2 cell_idx = floor(p);                         // integer cell coordinate
float animation = floor(iTime*.125 + offset);     // quantised time → slow flicker
float rnd = hash(vec3(cell_idx, animation));      // per-cell random value

float subpixel = floor(fract(p.x) * 3.);         // 0, 1, or 2 (R, G, B column)
vec3 RGB = vec3(hash(...R), hash(...G), hash(...B));  // per-channel random colour
vec3 color = RGB * vec3(subpixel==0, subpixel==1, subpixel==2); // isolate channel

vec2 q = .5 + .5*cos(2*PI*p*vec2(3,1) - PI);    // cosine dot envelope
return color * (q.x * q.y) * float(rnd > 0.5);  // mask by threshold noise

// mainImage
vec2 p = grid_dim * (zoom * uv + iTime*.25);     // animated + zoomed coords
color = pow(color, vec3(1./2.2));                 // gamma correction
```

---

## Dock adaptation notes

| Concern | Decision |
|---|---|
| Y-axis flip | Shadertoy y=0 at bottom; compute `fragCoord = float2(in.uv.x, 1.0 - in.uv.y) * resolution` before UV derivation |
| Mouse zoom | Original uses mouse Y for zoom. Map `u.indicatorOpacity` to zoom instead: `zoom = 1.0 + u.indicatorOpacity * 0.5` — dock zooms in slightly on hover |
| `hash(vec3)` | Provide as `subpixel_hash(float3)` to avoid collision with `crt_random` |
| Argument order | `hash_cnt++` inside constructor args has unspecified evaluation order in C++/MSL — expand to sequential named variables |
| Bool → float | MSL comparison returns `bool`; wrap with `float(...)` for use in `float3` constructor |
| `PI` | Replace with `M_PI_F` |
| Alpha | Output `float4(color, 1.0)`; `cornerMaskFragment` handles rounded corners |
| CRT passes | Not needed — `useCRT` stays false for `.subpixel` |

---

## GLSL → MSL translation table

| GLSL | MSL |
|---|---|
| `iTime` | `u.time` |
| `iResolution.xy` | `u.resolution` |
| `fragCoord` (y=0 bottom) | `float2(in.uv.x, 1.0 - in.uv.y) * u.resolution` |
| `vec2` / `vec3` / `vec4` | `float2` / `float3` / `float4` |
| `PI` | `M_PI_F` |
| `hash(vec3)` | `subpixel_hash(float3)` |
| `float(rnd > 0.5)` | `float(rnd > 0.5)` |
| `vec3(subpixel==0., ...)` | `float3(float(subpixel==0.0), float(subpixel==1.0), float(subpixel==2.0))` |
| `hash_cnt++` in args | Sequential assignments before constructor |
| `iMouse` zoom | `u.indicatorOpacity * 0.5` |
| `pow(color, vec3(1./2.2))` | `pow(color, float3(1.0 / 2.2))` |

---

## Phase 1 — Add `subpixel` case to `ReactiveStyle`

**File:** `DeskMat/AppEnums.swift`

```swift
enum ReactiveStyle: String, CaseIterable {
    case lockOn     = "Lock-On"
    case liquidFill = "Liquid Fill"
    case rainbow    = "Rainbow"
    case dvd        = "DVD"
    case eighties   = "80s"
    case voronoi    = "Voronoi"
    case subpixel   = "Subpixel"
}
```

**Acceptance criteria:**
- `"Subpixel"` appears in the Reactive Style dropdown.
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
    case .subpixel:   return "subpixelFragment"
    }
}
```

**Acceptance criteria:**
- Switching to Subpixel calls `rebuildPipeline()` with `"subpixelFragment"`.
- Dock renders nothing (pipeline miss) until Phase 3.

---

## Phase 3 — Write `subpixelFragment` in Metal

**File:** `DeskMat/ReactiveShaders.metal`

Append after `voronoiFragment`.

### Hash helper

```metal
// MARK: - Subpixel RGB Grid

float subpixel_hash(float3 p) {
    p = fract(p * 0.1031);
    p += dot(p, p.yzx + 33.33);
    return fract((p.x + p.y) * p.z);
}
```

### Grid pattern helper

```metal
float3 subpixel_dot_grid_pattern(float2 p, float t) {
    float2 cell_idx = floor(p);

    float animation_offset = subpixel_hash(float3(cell_idx, 0.0));
    float animation        = floor(t * 0.125 + animation_offset);
    float rnd              = subpixel_hash(float3(cell_idx, animation));

    float subpix = floor(fract(p.x) * 3.0);

    float r = subpixel_hash(float3(cell_idx, rnd + 1.0));
    float g = subpixel_hash(float3(cell_idx, rnd + 2.0));
    float b = subpixel_hash(float3(cell_idx, rnd + 3.0));
    float3 RGB = float3(r, g, b);

    float3 mask  = float3(float(subpix == 0.0), float(subpix == 1.0), float(subpix == 2.0));
    float3 color = RGB * mask;

    float2 q = 0.5 + 0.5 * cos(2.0 * M_PI_F * p * float2(3.0, 1.0) - M_PI_F);
    return color * (q.x * q.y) * float(rnd > 0.5);
}
```

### Fragment function

```metal
fragment float4 subpixelFragment(VertexOut in [[stage_in]],
                                  constant Uniforms& u [[buffer(0)]]) {
    float2 resolution = u.resolution;
    float2 fragCoord  = float2(in.uv.x, 1.0 - in.uv.y) * resolution;

    float2 uv = (2.0 * fragCoord - resolution) / resolution.y;

    // Hover zoom: expands grid slightly when mouse is over the dock
    float zoom = 1.0 + u.indicatorOpacity * 0.5;

    const float grid_dim = 5.0;
    float2 p = grid_dim * (zoom * uv + u.time * 0.25);

    float3 color = subpixel_dot_grid_pattern(p, u.time);

    color = pow(color, float3(1.0 / 2.2));

    return float4(color, 1.0);
}
```

**Acceptance criteria:**
- Selecting Subpixel shows an animated grid of R/G/B dot cells that slowly flicker on and off.
- The grid scrolls continuously.
- Hovering over the dock zooms the grid in slightly.
- Dock corners are masked by the corner mask pass.
- All other styles still work correctly.

---

## Phase 4 — Polish (optional / post-ship)

| Idea | Notes |
|---|---|
| Grid density | Expose `grid_dim` (default 5) as a uniform; higher = more, smaller cells |
| Flicker speed | Tune the `0.125` multiplier for faster or slower cell toggling |
| Scroll speed | Tune the `0.25` multiplier on `u.time * 0.25` |
| Hover response | Currently zooms; could instead boost brightness via `u.indicatorOpacity` |
| Colour palette | Replace per-channel random RGB with a fixed palette (e.g. only cyan/magenta/yellow) |

---

## Out of scope

- True physical subpixel rendering or font hinting.
- Per-cell click interaction.
- Rendering outside the dock's rounded-rect bounds.
