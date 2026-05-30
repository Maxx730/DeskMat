# Warp Speed Shader — Implementation Plan

Port the Interstellar shader by Hazel Quantock to Metal and wire it into the Reactive
background system as a selectable style named **Warp Speed**.

---

## License

Original by Hazel Quantock, licensed under **CC0** (public domain).
No restrictions — commercial use is fine.

---

## What the shader does

20 star-field layers are stepped along a perspective ray from screen centre. Each layer
samples a hash at its current integer grid cell to get a depth value `z`. That depth is
animated by `offset` (time-driven), creating a parallax rush toward the viewer. Stars are
tinted with a 3-channel doppler stripe: leading edge blue-shifts, trailing edge red-shifts,
centre is white — producing a motion-blur streak for fast nearby stars. `speed` oscillates
with `cos(offset)`, giving a pulsing acceleration. Gamma (2.2) decode is applied at the end
to reproduce the correct perceptual brightness.

---

## Key adaptations

| Concern | Decision |
|---|---|
| `iChannel0` noise texture | Replace with `warp_noise(int2)` hash — no texture asset needed |
| `Rand()` function | Unused in `mainImage` — omit |
| `ToLinear` / `ToGamma` | Keep gamma decode (2.2) for correct perceptual output |
| Y-axis flip | Apply standard flip: `fragCoord = float2(in.uv.x, 1.0 - in.uv.y) * resolution` |
| Dock aspect ratio | `ray.xy` normalised by `resolution.x` — vertical range is tiny on the wide dock, stars spread across the full width naturally |
| `ivec2` | `int2` in MSL |
| `vec3(0)` in `max()` | `float3(0.0)` |
| Helper naming | `warp_noise` |

---

## GLSL → MSL translation table

| GLSL | MSL |
|---|---|
| `iTime` | `u.time` |
| `iResolution.xy` | `u.resolution` |
| `fragCoord` (y=0 bottom) | `float2(in.uv.x, 1.0 - in.uv.y) * u.resolution` |
| `vec2 / vec3 / vec4` | `float2 / float3 / float4` |
| `ivec2` | `int2` |
| `texture(iChannel0, uv, -100.0).x` | `warp_noise(int2(pos.xy))` |
| `pow(col, vec3(1.0/GAMMA))` | `pow(col, float3(1.0/2.2))` |
| `max(vec3(0), …)` | `max(float3(0.0), …)` |

---

## Phase 1 — Add `warpSpeed` case to `ReactiveStyle`

**File:** `DeskMat/AppEnums.swift`

```swift
case electro   = "Electro"
case warpSpeed = "Warp Speed"
```

---

## Phase 2 — Route `fragmentShaderName`

**File:** `DeskMat/ReactiveBackgroundView.swift`

```swift
case .warpSpeed: return "warpSpeedFragment"
```

---

## Phase 3 — Write `warpSpeedFragment` in Metal

**File:** `DeskMat/ReactiveShaders.metal`

Append after `electroFragment`.

```metal
// MARK: - Warp Speed
// Port of "Interstellar" by Hazel Quantock (CC0)
// Original: shadertoy.com/view/Xdl3D2

float warp_noise(int2 xi) {
    float2 p = float2(xi) + 0.5;
    p = fract(p * float2(0.1031, 0.1030));
    p += dot(p, p + 33.33);
    return fract(p.x + p.y);
}

fragment float4 warpSpeedFragment(VertexOut in [[stage_in]],
                                   constant Uniforms& u [[buffer(0)]]) {
    float2 resolution = u.resolution;
    float2 fragCoord  = float2(in.uv.x, 1.0 - in.uv.y) * resolution;

    float3 ray;
    ray.xy = 2.0 * (fragCoord.xy - resolution.xy * 0.5) / resolution.x;
    ray.z  = 1.0;

    float offset = u.time * 0.5;
    float speed2 = (cos(offset) + 1.0) * 2.0;
    float speed  = speed2 + 0.1;
    offset += sin(offset) * 0.96;
    offset *= 2.0;

    float3 col = float3(0.0);

    float3 stp = ray / max(abs(ray.x), abs(ray.y));
    float3 pos = 2.0 * stp + 0.5;

    for (int i = 0; i < 20; i++) {
        float z = warp_noise(int2(pos.xy));
        z = fract(z - offset);
        float d = 50.0 * z - pos.z;
        float w = pow(max(0.0, 1.0 - 8.0 * length(fract(pos.xy) - 0.5)), 2.0);
        float3 c = max(float3(0.0), float3(
            1.0 - abs(d + speed2 * 0.5) / speed,
            1.0 - abs(d)                / speed,
            1.0 - abs(d - speed2 * 0.5) / speed
        ));
        col += 1.5 * (1.0 - z) * c * w;
        pos += stp;
    }

    col = pow(col, float3(1.0 / 2.2));
    return float4(col, 1.0);
}
```

**Acceptance criteria:**
- Selecting Warp Speed shows streaking star trails rushing toward the viewer.
- Speed pulses over time via the `cos(offset)` oscillation.
- Stars are blue/white/red depending on their relative depth.
- Dock corners are masked by the corner mask pass.
- All other styles still work correctly.

---

## Phase 4 — Polish (optional / post-ship)

| Idea | Notes |
|---|---|
| Star density | Increase loop count from 20 → 30 for denser field (watch GPU cost) |
| Base speed | Multiply `u.time * 0.5` by a configurable factor |
| Hover boost | Scale `speed` by `1.0 + u.indicatorOpacity * 2.0` to surge on hover |
| Colour tint | Replace hardcoded doppler RGB with a user-configurable hue offset |

---

## Out of scope

- Real texture-based noise (hash approximation is visually equivalent)
- Rendering outside the dock's rounded-rect bounds
