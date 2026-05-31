# Starfield Shader — Implementation Plan

Port the procedural starfield shader to Metal and wire it into the Reactive background
system as a selectable style named **Starfield**.

---

## License

Original shader is unlicensed / public domain (no attribution required).
No commercial concerns.

---

## What the shader does

8 depth layers of star fields are composited using a loop over `i = 0..1` in steps of 1/8.
Each layer has a different zoom level (15 → 0.05 from far to near) and fades in/out via
`smoothstep`. A camera path oscillates via `sin`/`cos` and applies a slow rotation. Each
star is resolved in a 3×3 neighbourhood loop, computing a point light term, a glow bloom
term, and a 4-ray diffraction spike. Stars are tinted blue→orange based on hash, and
warm-white mixed in. Gamma (0.8 power), vignette, film grain noise, and a soft bloom
pass finish the image.

---

## Key adaptations

| Concern | Decision |
|---|---|
| `mat2 rot(a)` | `float2x2 sf_rot(a)` — columns: `float2(c,s)`, `float2(-s,c)` |
| `p_uv *= rot(...)` | `p_uv = p_uv * sf_rot(...)` (row-vector × matrix, same semantics in MSL) |
| `vec2(float(x), float(y))` | `float2(float(x), float(y))` |
| `hash12 / hash22` | `sf_hash12 / sf_hash22` to avoid name collisions |
| `iTime` | `u.time` |
| `iResolution.xy` | `u.resolution` |
| `fragCoord` (y=0 bottom) | `float2(in.uv.x, 1.0 - in.uv.y) * u.resolution` |
| `screenUv = fragCoord / iResolution.xy` | `in.uv` (already normalised, y already correct for `length(…-0.5)`) |
| No texture | Fully procedural — no asset needed |

---

## GLSL → MSL translation table

| GLSL | MSL |
|---|---|
| `vec2 / vec3 / vec4` | `float2 / float3 / float4` |
| `mat2` | `float2x2` |
| `mat2(c,-s,s,c)` | `float2x2(float2(c,s), float2(-s,c))` |
| `v *= mat2(...)` | `v = v * float2x2(...)` |
| `5e-4` / `8e-5` / `1e3` | same literal syntax valid in MSL |
| `iTime` | `u.time` |
| `iResolution.xy` | `u.resolution` |

---

## Phase 1 — Add `starfield` case to `ReactiveStyle`

**File:** `DeskMat/AppEnums.swift`

```swift
case warpSpeed  = "Warp Speed"
case starfield  = "Starfield"
```

---

## Phase 2 — Route `fragmentShaderName`

**File:** `DeskMat/ReactiveBackgroundView.swift`

```swift
case .starfield: return "starfieldFragment"
```

---

## Phase 3 — Write `starfieldFragment` in Metal

**File:** `DeskMat/ReactiveShaders.metal` — append after `warpSpeedFragment`.

```metal
// MARK: - Starfield

float sf_hash12(float2 p) {
    float3 p3 = fract(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float2 sf_hash22(float2 p) {
    float3 p3 = fract(float3(p.xyx) * float3(0.1031, 0.103, 0.0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

float2x2 sf_rot(float a) {
    float s = sin(a), c = cos(a);
    return float2x2(float2(c, s), float2(-s, c));
}

float3 sf_getStarField(float2 uv, float zoom, float time, float seed) {
    float2 gv  = fract(uv * zoom) - 0.5;
    float2 id  = floor(uv * zoom);
    float3 col = float3(0.0);
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            float2 offs = float2(float(x), float(y));
            float2 n    = sf_hash22(id + offs + seed);
            float pTime = time * (0.3 + n.x * 0.7) + n.y * 6.28;
            float size  = (0.04 + 0.12 * sf_hash12(id + offs + seed + 121.3))
                        * (sin(pTime) * 0.5 + 0.5);
            float2 p    = offs + n - 0.5;
            float  d    = length(gv - p);
            float3 starCol = mix(float3(0.5, 0.7, 1.0),
                                 float3(1.0, 0.5, 0.3),
                                 sf_hash12(id + offs + seed + 45.1));
            starCol = mix(starCol, float3(1.0, 0.9, 0.7), n.x * n.y);
            float light  = (size * 0.015) / (d + 5e-4);
            float glow   = (size * 0.003) / (d * d + 8e-5);
            float2 r_uv  = (gv - p) * sf_rot(pTime * 0.5);
            float  rays  = pow(max(0.0, 1.0 - abs(r_uv.x * r_uv.y * 1e3)), 12.0)
                         * (size * 0.1 / (d + 0.01));
            rays += pow(max(0.0, 1.0 - abs(r_uv.x)), 50.0) * (size * 0.05 / (d + 0.01));
            col += (light + glow + rays) * starCol;
        }
    }
    return col;
}

fragment float4 starfieldFragment(VertexOut in [[stage_in]],
                                   constant Uniforms& u [[buffer(0)]]) {
    float2 resolution = u.resolution;
    float2 fragCoord  = float2(in.uv.x, 1.0 - in.uv.y) * resolution;

    float2 uv = (fragCoord - 0.5 * resolution) / resolution.y;
    float  t  = u.time * 0.15;

    float2 camPath = float2(sin(t * 0.5), cos(t * 0.3)) * 2.0;
    float  camRot  = sin(t * 0.2) * 0.4;

    float3 finalCol = float3(0.0);
    float  noise    = sf_hash12(fragCoord + u.time);

    for (float i = 0.0; i < 1.0; i += 1.0 / 8.0) {
        float  depth = fract(i - t * 0.5);
        float  zoom  = mix(15.0, 0.05, depth);
        float  fade  = smoothstep(0.0, 0.4, depth) * smoothstep(1.0, 0.8, depth);
        float2 p_uv  = uv;
        p_uv = p_uv * sf_rot(camRot * depth);
        p_uv += camPath * depth;
        finalCol += sf_getStarField(p_uv, zoom, u.time, i * 951.4) * fade;
    }

    finalCol  = pow(finalCol, float3(0.8));
    finalCol *= 1.2;

    float vign = length(in.uv - 0.5);
    finalCol *= smoothstep(1.2, 0.3, vign);
    finalCol += (noise - 0.5) * 0.012;

    float3 bloom = finalCol * finalCol;
    finalCol += bloom * 0.3;
    finalCol = mix(finalCol,
                   float3(dot(finalCol, float3(0.299, 0.587, 0.114))),
                   -0.1);

    return float4(clamp(finalCol, 0.0, 1.0), 1.0);
}
```

**Acceptance criteria:**
- Selecting Starfield shows a layered star field with parallax depth.
- Stars twinkle and have diffraction rays.
- Camera slowly drifts and rotates.
- Dock corners are masked by the corner mask pass.
- All other styles still work correctly.

---

## Phase 4 — Polish (optional / post-ship)

| Idea | Notes |
|---|---|
| Hover speed boost | Scale `t` by `1.0 + u.indicatorOpacity * 2.0` to rush forward on hover |
| Layer count | Change `1.0/8.0` step to `1.0/12.0` for denser depth (GPU cost ×1.5) |
| Colour tint | Add a configurable base hue shift to `starCol` |
| Film grain intensity | Expose `0.012` noise coefficient as a setting |
