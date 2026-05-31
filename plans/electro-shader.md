# Electro Shader — Implementation Plan

Port the Humus Electro demo shader to Metal and wire it into the Reactive
background system as a selectable style named **Electro**.

---

## ⚠️ License Notice

The Simplex noise implementation used by this shader is licensed under
**CC BY-NC-SA 3.0** (attribution, non-commercial, share-alike).  
Original: https://www.shadertoy.com/view/XsX3zB by Nikita Miropolskiy.

**Non-commercial** means this code cannot be used in a paid/commercial product
without separate permission. DeskMat Pro is a commercial product. Confirm
licensing is acceptable before shipping — options include:
- Replacing the simplex implementation with a public-domain alternative
- Contacting the original author for a commercial licence
- Removing this style before release

---

## What the shader does

A horizontal glowing electric arc (like a plasma bolt or lightning band) that
ripples across the screen, driven by 4-octave 3D simplex noise. The noise is
sampled at a 3D point whose z-axis is `time * 0.4`, producing smooth temporal
animation. A parabolic mask (`t`) peaks at `uv.x = 0` and fades toward the
edges, confining the glow to the centre of the screen. The final colour is
raised to the 4th power for punchy contrast, producing a bright lavender/purple
core that fades sharply to black.

---

## Shader walkthrough

```glsl
// Centered [-1,1] UV
uv = fragCoord / resolution * 2 - 1;

// Aspect-ratio UV for noise input (not centred)
p = fragCoord / resolution.x;         // y range ≈ 0..height/width (small on dock)
p3 = vec3(p, time * 0.4);             // 3D noise coord — z scrolls over time

intensity = noise(p3 * 12 + 12);      // 4-octave simplex noise

// Parabolic mask — peaks at x=0, fades to 0 at x=±1
t = clamp(-uv.x * uv.x * 0.16 + 0.15, 0, 1);

// Vertical distance from noise-warped horizontal centre line
y = abs(intensity * -t + uv.y);

// Very soft falloff (pow 0.2 ≈ root-5 → broad bright glow)
g = pow(y, 0.2);

col = vec3(1.70, 1.48, 1.78);     // lavender base colour
col = col * (1 - g);               // fade to black away from arc
col = col^4;                       // two squarings for contrast punch
```

---

## Dock adaptation notes

| Concern | Decision |
|---|---|
| Y-axis flip | Apply standard flip: `fragCoord = float2(in.uv.x, 1.0 - in.uv.y) * resolution`. The arc uses `abs(…uv.y)` so mirroring has no visual effect |
| `p = fragCoord / resolution.x` | Keep as-is — this is intentional aspect-ratio normalisation for the noise space |
| Dock aspect ratio | Dock is very wide (~19:1). The parabolic mask `t = -uv.x²*0.16 + 0.15` uses the full [-1,1] x range so the arc spans the full width naturally |
| Helper naming | Prefix all helpers: `electro_random3`, `electro_simplex3d`, `electro_noise` to avoid collisions |
| `const float F3/G3` | Declare as `const float` locals inside `electro_simplex3d` |
| `vec4 w, d` declared together | Declare separately in MSL: `float4 w; float4 d;` |
| Alpha | Output `float4(col, 1.0)`; `cornerMaskFragment` handles rounded corners |
| CRT passes | Not needed — `useCRT` stays false for `.electro` |

---

## GLSL → MSL translation table

| GLSL | MSL |
|---|---|
| `iTime` | `u.time` |
| `iResolution.xy` | `u.resolution` |
| `fragCoord` (y=0 bottom) | `float2(in.uv.x, 1.0 - in.uv.y) * u.resolution` |
| `vec2` / `vec3` / `vec4` | `float2` / `float3` / `float4` |
| `const float F3 = …` | `const float F3 = …` (inside function) |
| `vec4 w, d;` | `float4 w; float4 d;` |
| `step(vec3(0.0), x - x.yzx)` | `step(float3(0.0), x - x.yzx)` |
| `max(0.6 - w, 0.0)` | `max(0.6 - w, 0.0)` |
| `dot(d, vec4(52.0))` | `dot(d, float4(52.0))` |
| `fract(x)` | `fract(x)` |
| `floor(x)` | `floor(x)` |
| `clamp(x, 0., 1.)` | `clamp(x, 0.0, 1.0)` |
| `pow(y, 0.2)` | `pow(y, 0.2)` |
| `random3` / `simplex3d` / `noise` | `electro_random3` / `electro_simplex3d` / `electro_noise` |

---

## Phase 1 — Add `electro` case to `ReactiveStyle`

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
    case electro    = "Electro"
}
```

**Acceptance criteria:**
- `"Electro"` appears in the Reactive Style dropdown.
- No rendering change yet.

---

## Phase 2 — Route `fragmentShaderName`

**File:** `DeskMat/ReactiveBackgroundView.swift`

```swift
case .electro: return "electroFragment"
```

**Acceptance criteria:**
- Switching to Electro calls `rebuildPipeline()` with `"electroFragment"`.
- Dock renders nothing (pipeline miss) until Phase 3.

---

## Phase 3 — Write `electroFragment` in Metal

**File:** `DeskMat/ReactiveShaders.metal`

Append after `glowFragment`.

```metal
// MARK: - Electro
// Port of Humus Electro demo (http://humus.name/index.php?page=3D&ID=35)
// Simplex noise by Nikita Miropolskiy (CC BY-NC-SA 3.0)
// https://www.shadertoy.com/view/XsX3zB

float3 electro_random3(float3 c) {
    float j = 4096.0 * sin(dot(c, float3(17.0, 59.4, 15.0)));
    float3 r;
    r.z = fract(512.0 * j);
    j *= 0.125;
    r.x = fract(512.0 * j);
    j *= 0.125;
    r.y = fract(512.0 * j);
    return r - 0.5;
}

float electro_simplex3d(float3 p) {
    const float F3 = 0.3333333;
    const float G3 = 0.1666667;

    float3 s = floor(p + dot(p, float3(F3)));
    float3 x = p - s + dot(s, float3(G3));

    float3 e  = step(float3(0.0), x - x.yzx);
    float3 i1 = e * (1.0 - e.zxy);
    float3 i2 = 1.0 - e.zxy * (1.0 - e);

    float3 x1 = x - i1 + G3;
    float3 x2 = x - i2 + 2.0 * G3;
    float3 x3 = x - 1.0 + 3.0 * G3;

    float4 w;
    float4 d;

    w.x = dot(x,  x);
    w.y = dot(x1, x1);
    w.z = dot(x2, x2);
    w.w = dot(x3, x3);

    w = max(0.6 - w, 0.0);

    d.x = dot(electro_random3(s),       x);
    d.y = dot(electro_random3(s + i1),  x1);
    d.z = dot(electro_random3(s + i2),  x2);
    d.w = dot(electro_random3(s + 1.0), x3);

    w *= w;
    w *= w;
    d *= w;

    return dot(d, float4(52.0));
}

float electro_noise(float3 m) {
    return  0.5333333 * electro_simplex3d(m)
          + 0.2666667 * electro_simplex3d(2.0 * m)
          + 0.1333333 * electro_simplex3d(4.0 * m)
          + 0.0666667 * electro_simplex3d(8.0 * m);
}

fragment float4 electroFragment(VertexOut in [[stage_in]],
                                 constant Uniforms& u [[buffer(0)]]) {
    float2 resolution = u.resolution;
    float2 fragCoord  = float2(in.uv.x, 1.0 - in.uv.y) * resolution;

    float2 uv = fragCoord / resolution * 2.0 - 1.0;

    float2 p  = fragCoord / resolution.x;
    float3 p3 = float3(p, u.time * 0.4);

    float intensity = electro_noise(p3 * 12.0 + 12.0);

    float t = clamp(-uv.x * uv.x * 0.16 + 0.15, 0.0, 1.0);
    float y = abs(intensity * -t + uv.y);

    float g = pow(y, 0.2);

    float3 col = float3(1.70, 1.48, 1.78);
    col = col * -g + col;
    col = col * col;
    col = col * col;

    return float4(col, 1.0);
}
```

**Acceptance criteria:**
- Selecting Electro shows a glowing horizontal arc that ripples with noise.
- The arc animates continuously over time.
- The glow is brightest at centre and fades toward the dock edges.
- Dock corners are masked by the corner mask pass.
- All other styles still work correctly.

---

## Phase 4 — Polish (optional / post-ship)

| Idea | Notes |
|---|---|
| Arc colour | Replace `float3(1.70, 1.48, 1.78)` with a user-configurable colour |
| Arc intensity | Expose the `0.16` parabola coefficient to widen/narrow the glow zone |
| Speed | Multiply `u.time * 0.4` by a configurable factor |
| Hover pulse | Scale `t` by `1.0 + u.indicatorOpacity * 0.5` to broaden the arc on hover |
| Noise frequency | The `12.0` multiplier on `p3` controls ripple density — expose as a setting |
| License | Replace simplex implementation with a public-domain alternative before commercial release |

---

## Out of scope

- True 3D noise texture (original used a precomputed 3D texture; this uses procedural simplex)
- Rendering outside the dock's rounded-rect bounds
