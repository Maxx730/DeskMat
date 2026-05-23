# Joker Shader — Implementation Plan

Port the Balatro spinning paint shader (by localthunk) to Metal and wire it into
the Reactive background system as a selectable style named **Joker**.

---

## What the shader does

A swirling, paint-like turbulence effect in red, blue, and dark teal. UV
coordinates are first snapped to a pixel grid (pixelation filter), then
transformed into polar form and rotated by a spiral warp. The warped UVs are
fed into 5 iterations of sin/cos turbulence to produce organic flowing shapes.
A final colour blend maps the turbulence output to three configurable colours
with a highlight lighting term.

---

## Shader walkthrough

```glsl
// Pixel snap — prevents aliasing on the swirl
pixel_size = length(screenSize) / PIXEL_FILTER;
uv = floor(screen_coords / pixel_size) * pixel_size  → centred + normalised

// Spiral warp — rotates each pixel by an angle that depends on its radius
new_pixel_angle = atan(uv.y, uv.x) + speed
                - SPIN_EASE * 20 * (SPIN_AMOUNT * uv_len + (1 - SPIN_AMOUNT));
uv = polar_to_cartesian(uv_len, new_pixel_angle) - mid;

// Turbulence — 5-iteration sin/cos fold
uv *= 30; speed = iTime * SPIN_SPEED;
for 5 iterations: uv2 += sin(max(uv)) + uv; uv += cos/sin terms; uv -= ...

// Colour blend
paint_res → [0, 2] scalar from length(uv) after turbulence
c1p, c2p, c3p → soft blend weights for COLOUR_1, COLOUR_2, COLOUR_3
light → additive highlight on bright regions
```

---

## Dock adaptation notes

| Concern | Decision |
|---|---|
| Y-axis flip | Not required — the effect is centred and radially symmetric; top-left vs bottom-left origin produces the same visual |
| `IS_ROTATE` | Original is `false` — the spin angle is static (`SPIN_ROTATION * SPIN_EASE * 0.2 + 302.2`). Keep it false; only the turbulence loop uses `iTime` |
| `atan(y, x)` | MSL uses `atan2(y, x)` |
| Constants | Declare as `const` locals inside `joker_effect()` to avoid Metal address-space issues |
| `PIXEL_FILTER` | 745.0 was tuned for a ~916px diagonal (800×450). The dock's logical diagonal (~1602 for 1600×84) gives `pixel_size ≈ 2.15pt` — acceptable, tunable in Phase 4 |
| Alpha | Output `float4(color.rgb, 1.0)`; `cornerMaskFragment` handles rounded corners |
| CRT passes | Not needed — `useCRT` stays false for `.joker` |

---

## GLSL → MSL translation table

| GLSL | MSL |
|---|---|
| `iTime` | `u.time` |
| `iResolution.xy` | `u.resolution` |
| `vec2` / `vec4` | `float2` / `float4` |
| `atan(y, x)` | `atan2(y, x)` |
| `length(v)` | `length(v)` |
| `floor(x)` | `floor(x)` |
| `cos(x)` / `sin(x)` | `cos(x)` / `sin(x)` |
| `min(a,b)` / `max(a,b)` | `min(a,b)` / `max(a,b)` |
| `#define COLOUR_1 vec4(...)` | `const float4 COLOUR_1 = float4(...)` inside function |
| `#define IS_ROTATE false` | omit — bake the `false` branch directly |
| `void mainImage(out vec4, vec2)` | `fragment float4 jokerFragment(...)` |

---

## Phase 1 — Add `joker` case to `ReactiveStyle`

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
    case joker      = "Joker"
}
```

**Acceptance criteria:**
- `"Joker"` appears in the Reactive Style dropdown.
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
    case .joker:      return "jokerFragment"
    }
}
```

**Acceptance criteria:**
- Switching to Joker calls `rebuildPipeline()` with `"jokerFragment"`.
- Dock renders nothing (pipeline miss) until Phase 3.

---

## Phase 3 — Write `jokerFragment` in Metal

**File:** `DeskMat/ReactiveShaders.metal`

Append after `subpixelFragment`.

```metal
// MARK: - Joker (Balatro spin shader)
// Original by localthunk (https://www.playbalatro.com)

float4 joker_effect(float2 screenSize, float2 screen_coords, float t) {
    const float SPIN_ROTATION = -2.0;
    const float SPIN_SPEED    =  7.0;
    const float CONTRAST      =  3.5;
    const float LIGHTING      =  0.4;
    const float SPIN_AMOUNT   =  0.25;
    const float PIXEL_FILTER  =  745.0;
    const float SPIN_EASE     =  1.0;
    const float4 COLOUR_1 = float4(0.871, 0.267, 0.231, 1.0);
    const float4 COLOUR_2 = float4(0.0,   0.42,  0.706, 1.0);
    const float4 COLOUR_3 = float4(0.086, 0.137, 0.145, 1.0);

    float pixel_size = length(screenSize) / PIXEL_FILTER;
    float2 uv = (floor(screen_coords * (1.0 / pixel_size)) * pixel_size
                 - 0.5 * screenSize) / length(screenSize);
    float uv_len = length(uv);

    // Static rotation (IS_ROTATE = false)
    float speed = (SPIN_ROTATION * SPIN_EASE * 0.2) + 302.2;
    float new_pixel_angle = atan2(uv.y, uv.x) + speed
                          - SPIN_EASE * 20.0 * (SPIN_AMOUNT * uv_len + (1.0 - SPIN_AMOUNT));

    float2 mid = (screenSize / length(screenSize)) / 2.0;
    uv = float2(uv_len * cos(new_pixel_angle) + mid.x,
                uv_len * sin(new_pixel_angle) + mid.y) - mid;

    uv   *= 30.0;
    speed = t * SPIN_SPEED;
    float2 uv2 = float2(uv.x + uv.y);

    for (int i = 0; i < 5; i++) {
        uv2 += sin(max(uv.x, uv.y)) + uv;
        uv  += 0.5 * float2(cos(5.1123314 + 0.353 * uv2.y + speed * 0.131121),
                             sin(uv2.x - 0.113 * speed));
        uv  -= 1.0 * cos(uv.x + uv.y) - 1.0 * sin(uv.x * 0.711 - uv.y);
    }

    float contrast_mod = 0.25 * CONTRAST + 0.5 * SPIN_AMOUNT + 1.2;
    float paint_res    = min(2.0, max(0.0, length(uv) * 0.035 * contrast_mod));
    float c1p   = max(0.0, 1.0 - contrast_mod * abs(1.0 - paint_res));
    float c2p   = max(0.0, 1.0 - contrast_mod * abs(paint_res));
    float c3p   = 1.0 - min(1.0, c1p + c2p);
    float light = (LIGHTING - 0.2) * max(c1p * 5.0 - 4.0, 0.0)
                +  LIGHTING        * max(c2p * 5.0 - 4.0, 0.0);

    return (0.3 / CONTRAST) * COLOUR_1
         + (1.0 - 0.3 / CONTRAST) * (COLOUR_1 * c1p
                                    + COLOUR_2 * c2p
                                    + float4(c3p * COLOUR_3.rgb, c3p * COLOUR_1.a))
         + light;
}

fragment float4 jokerFragment(VertexOut in [[stage_in]],
                               constant Uniforms& u [[buffer(0)]]) {
    float4 color = joker_effect(u.resolution, in.uv * u.resolution, u.time);
    return float4(color.rgb, 1.0);
}
```

**Acceptance criteria:**
- Selecting Joker shows an animated swirling red/blue/teal paint effect across the dock.
- The turbulence animates continuously driven by time.
- Dock corners are masked by the corner mask pass.
- All other styles still work correctly.

---

## Phase 4 — Polish (optional / post-ship)

| Idea | Notes |
|---|---|
| Pixel filter | Expose `PIXEL_FILTER` as a uniform; lower = coarser, higher = sharper |
| Colours | Replace hardcoded `COLOUR_1/2/3` with user-configurable swatches |
| Spin amount | Expose `SPIN_AMOUNT` to control how tightly the spiral winds |
| Hover pulse | Boost `LIGHTING` via `u.indicatorOpacity` for a brightness surge on hover |
| IS_ROTATE | Enable time-based rotation (`speed = u.time * SPIN_ROTATION * SPIN_EASE * 0.2`) for continuous spin |

---

## Out of scope

- Per-card customisation (original Balatro context).
- Multiple simultaneous colour palettes.
- Rendering outside the dock's rounded-rect bounds.
