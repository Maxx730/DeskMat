# DVD Bounce Shader — Implementation Plan

Port the Shadertoy "DVD Bouncing Logo" shader (shadertoy.com/view/scjSDz,
logo SDF credited to tdhooper / shadertoy.com/view/wtcSzN) to Metal and wire
it into the Reactive background system as a selectable style named **DVD**.

---

## What the shader does

A vector DVD logo (built from signed-distance functions for the D, V, and C
glyphs with an italic shear) bounces around the dock interior. The logo color
cycles slowly through a full-spectrum palette. Subtle CRT scanlines and an
inner shadow add depth. The background is solid black — the dock becomes a
mini screensaver.

---

## Adaptation notes for the dock

| Concern | Decision |
|---|---|
| Background | Solid black (output alpha = rounded-rect mask), matching the screensaver aesthetic |
| Bounce region | Existing `bounce()` already works in UV [0,1] space; `u.resolution` replaces `iResolution.xy` |
| Y-axis flip | Shadertoy has y=0 at bottom; Metal UVs have y=0 at top-left. Flip before computing centred coords: `fragCoord.y = u.resolution.y − pixelPos.y` |
| Scanline frequency | Original `sin(fragCoord.y * PI * 1.8)` is tuned for a full screen. At ~84 px dock height the bands will be coarser — acceptable for now; adjust in Phase 4 if needed |
| Logo scale | `LOGO_SCALE 0.11` fits a 1080p screen. Will need to be reduced for the dock (dock is ~84 px tall; start with `0.06`) |
| Hover interaction | `u.indicatorOpacity` can boost logo brightness on hover — optional, Phase 4 |

---

## GLSL → MSL translation table

| GLSL | MSL |
|---|---|
| `iTime` | `u.time` |
| `iResolution.xy` | `u.resolution` |
| `fragCoord` | `float2(pixelPos.x, u.resolution.y - pixelPos.y)` (y-flipped) |
| `vec2 / vec3 / vec4` | `float2 / float3 / float4` |
| `mod(x, y)` | `fmod(x, y)` |
| `fract(x)` | `fract(x)` |
| `mix(a, b, t)` | `mix(a, b, t)` |
| `fwidth(d)` | `abs(dfdx(d)) + abs(dfdy(d))` — MSL has no `fwidth` builtin |
| `mat2(a,b,c,d)` | `float2x2(float2(a,b), float2(c,d))` (same column-major semantics) |
| `p * mat2(...)` | `p * float2x2(...)` — MSL row-vector × matrix matches GLSL |
| `void mainImage(out vec4, in vec2)` | `fragment float4 dvdFragment(...)` |
| `fragColor = vec4(col, 1.0)` | `return float4(col, alpha)` where alpha = roundedRectAlpha |
| `hsv2rgb` | Already defined in the file (rainbow shader); **do not redefine** |

---

## Functions to port (in order of dependency)

```
vmin, vmax          — trivial min/max of float2
ellip               — ellipse SDF using vmin
halfEllip           — half-ellipse SDF (clamps x)
dvd_d               — 'D' glyph SDF
dvd_v               — 'V' glyph SDF  
dvd_c               — 'C' / arc glyph SDF (the disc)
dvd                 — combines glyphs with italic shear
pal                 — cosine colour palette
spectrum            — wraps pal for rainbow output
bounce              — triangle-wave UV position over time
dvdFragment         — main fragment entry point
```

`fBox` and `hsv2rgb` are defined in the original but never called by the
render path — omit both.

---

## Phase 1 — Add `dvd` case to `ReactiveStyle`

**File:** `DeskMat/AppEnums.swift`

```swift
enum ReactiveStyle: String, CaseIterable {
    case lockOn     = "Lock-On"
    case liquidFill = "Liquid Fill"
    case rainbow    = "Rainbow"
    case dvd        = "DVD"
}
```

**Acceptance criteria:**
- `"DVD"` appears in the Reactive Style dropdown.
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
    }
}
```

**Acceptance criteria:**
- Switching to DVD calls `rebuildPipeline()` with `"dvdFragment"`.
- Dock renders nothing (pipeline miss) until Phase 3.

---

## Phase 3 — Write `dvdFragment` in Metal

**File:** `DeskMat/ReactiveShaders.metal`

Append after `rainbowFragment`. Full port below.

### Helpers

```metal
// MARK: - DVD Bounce

float dvd_vmin(float2 v) { return min(v.x, v.y); }
float dvd_vmax(float2 v) { return max(v.x, v.y); }

float dvd_ellip(float2 p, float2 s) {
    float m = dvd_vmin(s);
    return (length(p / s) * m) - m;
}

float dvd_halfEllip(float2 p, float2 s) {
    p.x = max(0.0, p.x);
    float m = dvd_vmin(s);
    return (length(p / s) * m) - m;
}

float dvd_glyph_d(float2 p) {
    float d  = dvd_halfEllip(p, float2(0.8, 0.5));
    d        = max(d, -p.x - 0.5);
    float d2 = dvd_halfEllip(p, float2(0.45, 0.3));
    d2       = max(d2, min(-p.y + 0.2, -p.x - 0.15));
    d        = max(d, -d2);
    return d;
}

float dvd_glyph_v(float2 p) {
    float2 pp = p;
    p.y += 0.7;
    p.x  = abs(p.x);
    float2 a = normalize(float2(1.0, -0.55));
    float d  = dot(p, a);
    float d2 = d + 0.3;
    p  = pp;
    d  = min(d,  -p.y + 0.3);
    d2 = min(d2, -p.y + 0.5);
    d  = max(d, -d2);
    d  = max(d, abs(p.x + 0.3) - 1.1);
    return d;
}

float dvd_glyph_c(float2 p) {
    p.y     += 0.95;
    float d  = dvd_ellip(p, float2(1.8, 0.25));
    float d2 = dvd_ellip(p, float2(0.45, 0.09));
    d        = max(d, -d2);
    return d;
}

float dvd_logo(float2 p) {
    p.y  -= 0.345;
    p.x  -= 0.035;
    p     = p * float2x2(float2(1.0, -0.2), float2(0.0, 1.0));  // italic shear
    float d = dvd_glyph_v(p);
    d = min(d, dvd_glyph_c(p));
    p.x += 1.3;
    d = min(d, dvd_glyph_d(p));
    p.x -= 2.4;
    d = min(d, dvd_glyph_d(p));
    return d;
}

float3 dvd_pal(float t, float3 a, float3 b, float3 c, float3 d) {
    return a + b * cos(6.28318 * (c * t + d));
}

float3 dvd_spectrum(float n) {
    return dvd_pal(n,
        float3(0.5, 0.5, 0.5),
        float3(0.5, 0.5, 0.5),
        float3(1.0, 1.0, 1.0),
        float3(0.0, 0.33, 0.67));
}

#define DVD_SCALE  0.06
#define DVD_SPD_X  0.23
#define DVD_SPD_Y  0.16

float2 dvd_bounce(float t, float2 res) {
    float aspect = res.x / res.y;
    float halfW  = 1.55 * DVD_SCALE / (2.0 * aspect);
    float halfH  = 0.85 * DVD_SCALE / 2.0;
    float yBias  = 0.2  * DVD_SCALE / 2.0;
    float2 lo    = float2(halfW, halfH - yBias);
    float2 hi    = float2(1.0 - halfW, 1.0 - halfH - yBias);
    float2 rng   = hi - lo;
    float px = fmod(t * DVD_SPD_X, rng.x * 2.0);
    float py = fmod(t * DVD_SPD_Y + rng.y * 0.61803, rng.y * 2.0);
    float cx = (px < rng.x) ? px : rng.x * 2.0 - px;
    float cy = (py < rng.y) ? py : rng.y * 2.0 - py;
    return lo + float2(cx, cy);
}
```

### Fragment function

```metal
fragment float4 dvdFragment(VertexOut in [[stage_in]],
                             constant Uniforms& u [[buffer(0)]]) {
    float2 uv       = in.uv;
    float2 pixelPos = uv * u.resolution;

    // Flip y to match Shadertoy convention (y=0 at bottom)
    float2 fc = float2(pixelPos.x, u.resolution.y - pixelPos.y);

    // Centred normalised coords, height in [-1, 1]
    float2 p = (-u.resolution + 2.0 * fc) / u.resolution.y;

    // Bouncing logo centre in UV space → centred coords
    float2 uvCenter = dvd_bounce(u.time, u.resolution);
    float2 move     = (uvCenter - 0.5) * float2(u.resolution.x / u.resolution.y, 1.0) * 2.0;

    // Spectrum colour
    float hue    = fmod(u.time * 0.06, 1.0);
    float3 logoc = dvd_spectrum(hue);

    // CRT scanlines
    float scan = 0.96 + 0.04 * sin(fc.y * 3.14159265 * 1.8);

    float3 col = float3(0.0) * scan;  // black background

    // DVD logo SDF
    float d  = dvd_logo((p - move) / DVD_SCALE);
    float aa = abs(dfdx(d)) + abs(dfdy(d));
    float mask = 1.0 - clamp(d / aa, 0.0, 1.0);

    col = mix(col, logoc, mask);

    // Inner shadow
    float innerMask = 1.0 - clamp((d + 0.06) / aa, 0.0, 1.0);
    col = mix(col, logoc * 0.25, innerMask * mask);

    col *= scan;

    // Gamma
    col = pow(max(col, float3(0.0)), float3(1.0 / 1.5));

    // Dock rounded-rect alpha mask
    float alpha = roundedRectAlpha(uv, u.resolution, u.cornerRadius);

    return float4(col, alpha);
}
```

**Acceptance criteria:**
- Selecting DVD shows a black dock with a small DVD logo bouncing inside it.
- The logo color cycles through the rainbow over ~17 seconds.
- CRT scanlines are subtly visible.
- The dock corners are correctly masked.
- Lock-On, Liquid Fill, and Rainbow styles still work.

---

## Phase 4 — Polish (optional / post-ship)

| Idea | Notes |
|---|---|
| Scanline density tuning | Scale frequency by `u.resolution.y / 1080.0` for consistent band width |
| Hover brightness boost | Multiply `logoc` by `1.0 + u.indicatorOpacity * 0.4` on hover |
| Configurable logo scale | `dvdLogoScale` AppStorage key; pass as uniform |
| Color-on-bounce | Flash to new hue exactly when the logo hits a wall (requires edge-detect in bounce) |
| Speed controls | Expose `dvdSpeedX` / `dvdSpeedY` sliders in Settings |

---

## Out of scope

- Rasterising an actual DVD bitmap image (SDF glyph construction is sufficient).
- Physics-accurate wall collision response.
- Rendering outside the dock's rounded-rect bounds.
