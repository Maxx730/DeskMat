# Tunnel Shader — Implementation Plan

Port the procedural dot-tunnel shader to Metal and wire it into the Reactive background
system as a selectable style named **Tunnel**.

---

## What the shader does

A camera flies through an infinite tunnel made of concentric rings of dots. Each ring has
`RING_POINTS` (128) evenly-spaced dots arranged angularly. `TUNNEL_LAYERS` (96) rings
scroll toward the viewer in depth, with radius expanding via perspective (`1 / pz²`). The
camera follows a smooth sinusoidal path (`TunnelPath`) that offsets both the ring centres
and the camera position, creating the illusion of a winding tunnel. Dots alternate between
two grey tones and fade by depth. Anti-aliased via `smoothstep` against a single-pixel
boundary.

---

## GLSL → MSL translation table

| GLSL | MSL |
|---|---|
| `vec2 / vec3 / vec4` | `float2 / float3 / float4` |
| `iTime` | `u.time` |
| `iResolution.xy` | `u.resolution` |
| `iResolution.y` | `u.resolution.y` |
| `fragCoord` (y=0 bottom) | `float2(in.uv.x, 1.0 - in.uv.y) * u.resolution` |
| `atan(y, x)` | `atan2(y, x)` |
| `mod(a, b)` | `fmod(a, b)` (MSL has `fmod`, but `mod` also works via the standard library) |
| Free functions | Prefixed `tn_` to avoid name collisions |
| `MixShape` uses `iResolution.y` | Pass `resY` as an explicit parameter |

---

## Key adaptations

| Concern | Decision |
|---|---|
| `sq(x)` | `tn_sq(x)` — trivial |
| `AngRep(uv, angle)` | `tn_AngRep` — `atan(y,x)` → `atan2(y,x)`, `mod` → `fmod` |
| `sdCircle(uv, r)` | `tn_sdCircle` — unchanged |
| `MixShape(sd, fill, target)` | `tn_MixShape(sd, fill, target, resY)` — passes `u.resolution.y` for the 1-pixel smoothstep |
| `TunnelPath(x)` | `tn_TunnelPath` — unchanged math |
| `POINT_SIZE / 2.0 / iResolution.y` | computed at shader entry using `u.resolution.y` |
| Speed reactivity | Multiply base `SPEED` by `mix(1.0, 2.5, u.indicatorOpacity)` so hovering the dock rushes the tunnel forward |
| Edge highlight | Enabled (consistent with other animated styles) |

---

## Phase 1 — Add `tunnel` case to `ReactiveStyle`

**File:** `DeskMat/AppEnums.swift`

```swift
enum ReactiveStyle: String, CaseIterable {
    case none      = "None"
    case electro   = "Electro"
    case starfield = "Starfield"
    case silky     = "Silky"
    case colors    = "Colors"
    case tunnel    = "Tunnel"   // ← add
}
```

---

## Phase 2 — Route `fragmentShaderName`

**File:** `DeskMat/ReactiveBackgroundView.swift`

```swift
var fragmentShaderName: String {
    switch reactiveStyle {
    case .none:      return ""
    case .electro:   return "electroFragment"
    case .starfield: return "starfieldFragment"
    case .silky:     return "silkyFragment"
    case .colors:    return "colorsFragment"
    case .tunnel:    return "tunnelFragment"   // ← add
    }
}
```

---

## Phase 3 — Enable edge highlight for Tunnel

**File:** `DeskMat/ReactiveBackgroundView.swift`

```swift
let useEdgeHighlight = reactiveStyle == .electro || reactiveStyle == .starfield
                    || reactiveStyle == .silky   || reactiveStyle == .colors
                    || reactiveStyle == .tunnel   // ← add
```

---

## Phase 4 — Write `tunnelFragment` in Metal

**File:** `DeskMat/ReactiveShaders.metal` — append after `colorsFragment` and before the
`// MARK: - Edge Highlight` block.

```metal
// MARK: - Tunnel

#define TN_TAU        6.2831853071795865
#define TN_LAYERS     96
#define TN_POINTS     128
#define TN_POINT_SIZE 1.8
#define TN_SPEED      0.7

float tn_sq(float x) { return x * x; }

float2 tn_AngRep(float2 uv, float angle) {
    float2 polar = float2(atan2(uv.y, uv.x), length(uv));
    polar.x = fmod(polar.x + angle * 0.5, angle) - angle * 0.5;
    return polar.y * float2(cos(polar.x), sin(polar.x));
}

float tn_sdCircle(float2 uv, float r) { return length(uv) - r; }

float3 tn_MixShape(float sd, float3 fill, float3 target, float resY) {
    float blend = smoothstep(0.0, 1.0 / resY, sd);
    return mix(fill, target, blend);
}

float2 tn_TunnelPath(float x) {
    float2 offs;
    offs.x = 0.2 * sin(TN_TAU * x * 0.5) + 0.4 * sin(TN_TAU * x * 0.2 + 0.3);
    offs.y = 0.3 * cos(TN_TAU * x * 0.3) + 0.2 * cos(TN_TAU * x * 0.1);
    offs  *= smoothstep(1.0, 4.0, x);
    return offs;
}

fragment float4 tunnelFragment(VertexOut in [[stage_in]],
                                constant Uniforms& u [[buffer(0)]]) {
    float2 res       = u.resolution / u.resolution.y;
    float2 fragCoord = float2(in.uv.x, 1.0 - in.uv.y) * u.resolution;
    float2 uv        = fragCoord / u.resolution.y - res * 0.5;

    float3 bg    = float3(17.0 / 255.0); // #111111
    float3 color = bg;

    float repAngle = TN_TAU / float(TN_POINTS);
    float pointSz  = TN_POINT_SIZE * 0.5 / u.resolution.y;

    float speed  = TN_SPEED * mix(1.0, 2.5, u.indicatorOpacity);
    float camZ   = u.time * speed;
    float2 camOffs = tn_TunnelPath(camZ);

    for (int i = 1; i <= TN_LAYERS; i++) {
        float pz = 1.0 - (float(i) / float(TN_LAYERS));

        pz -= fmod(camZ, 4.0 / float(TN_LAYERS));

        float2 offs    = tn_TunnelPath(camZ + pz) - camOffs;
        float  ringRad = 0.15 * (1.0 / tn_sq(pz * 0.8 + 0.4));

        if (abs(length(uv + offs) - ringRad) < pointSz * 1.5) {
            float2 aruv  = tn_AngRep(uv + offs, repAngle);
            float  pdist = tn_sdCircle(aruv - float2(ringRad, 0.0), pointSz);

            float3 ptColor = (fmod(float(i / 2), 2.0) == 0.0)
                             ? float3(1.0)
                             : float3(0.7);

            float shade = 1.0 - pz;
            color = tn_MixShape(pdist, ptColor * shade, color, u.resolution.y);
        }
    }

    return float4(color, 1.0);
}
```

**Acceptance criteria:**
- Selecting Tunnel shows a winding dot-ring tunnel flying toward the viewer.
- Hovering the dock visibly speeds up the tunnel scroll.
- Camera path curves smoothly; no popping at layer boundaries.
- Dock corners are clipped by the corner mask pass.
- All other reactive styles still work correctly.

---

## Phase 5 — Polish (optional / post-ship)

| Idea | Notes |
|---|---|
| Colour tint | Replace `float3(1.0)` / `float3(0.7)` with hue-shifted colours driven by depth |
| Hover colour shift | Lerp dot colour toward a highlight hue based on `u.indicatorOpacity` |
| Ring density | Expose `TN_LAYERS` / `TN_POINTS` as tunable constants |
| Depth fog | Multiply `ptColor * shade` by an additional exponential fog term for richer depth |
