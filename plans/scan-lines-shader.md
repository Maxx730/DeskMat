# Scan Lines Shader — Implementation Plan

Port the Godot scan lines shader to Metal and wire it into the Reactive
background system as a selectable style.

Source: https://godotshaders.com/shader/scan-lines/

---

## What the shader does

Two scan lines (one horizontal, one vertical) move randomly across the
surface. Each line jumps to a new random position on a fixed time
interval, interpolating smoothly between positions. Lines are rendered
as soft glowing bands using `smoothstep`. The background is a solid
fill color.

---

## Godot → Metal translation notes

| Godot | Metal equivalent |
|---|---|
| `TIME` | `u.time` |
| `UV` | `in.uv` |
| `TEXTURE` | Not needed — solid black background |
| `fill_color` | Hardcoded black (matches `backgroundColor`) |
| `use_texture_alpha` | Removed — no texture |
| `line_color` | Hardcoded green (`float3(0, 1, 0)`) initially |
| `line_thickness` | Hardcoded `0.01`, exposed as uniform later |
| `speed` | Hardcoded `1.0`, exposed as uniform later |

The `random()`, `highlight()`, and `point_to_color()` functions port
directly — they are pure float math with no Godot-specific features.

---

## Phase 1 — Add `scanLines` to `ReactiveStyle`

**File:** `DeskMat/AppEnums.swift`

```swift
enum ReactiveStyle: String, CaseIterable {
    case dot       = "Dot"
    case scanLines = "Scan Lines"
    case ripple    = "Ripple"
    case glow      = "Glow"
}
```

**Acceptance criteria:**
- `"Scan Lines"` appears in the Reactive Style dropdown in Settings.
- No other behaviour changes yet.

---

## Phase 2 — Route `fragmentShaderName` by style

Currently `fragmentShaderName` always returns `"dotFragment"`.
Change it to switch on `reactiveStyle` so the pipeline rebuilds to
the correct shader automatically when the style changes.

**File:** `DeskMat/ReactiveBackgroundView.swift`

```swift
var fragmentShaderName: String {
    switch reactiveStyle {
    case .dot:       return "dotFragment"
    case .scanLines: return "scanLinesFragment"
    case .ripple:    return "rippleFragment"
    case .glow:      return "glowFragment"
    }
}
```

Because `reactiveStyle.didSet` already calls `rebuildPipeline()`, no
other changes are needed — the pipeline will swap to the correct shader
the moment the user picks a different style.

**Acceptance criteria:**
- Changing the style picker calls `rebuildPipeline()` with the new
  function name.
- Selecting an unimplemented style (`ripple`, `glow`) causes
  `rebuildPipeline()` to fail silently (function not found in library)
  and render nothing — acceptable until those shaders are written.

---

## Phase 3 — Write `scanLinesFragment` in Metal

**File:** `DeskMat/ReactiveShaders.metal`

Port the Godot fragment logic. The `vertex()` fill-color step is
dropped — Metal's clear colour (black) handles the background.

```metal
// --- helpers ---

float random_sl(float2 uv) {
    return fract(sin(dot(uv, float2(12.9898, 78.233))) * 43758.5453123);
}

float highlight_sl(float point, float progress, float thickness) {
    return smoothstep(progress - thickness, progress, point)
         - smoothstep(progress, progress + thickness, point);
}

float point_to_color_sl(float2 uv, float2 point, float thickness) {
    return highlight_sl(uv.y, point.y, thickness)
         + highlight_sl(uv.x, point.x, thickness);
}

// --- fragment ---

fragment float4 scanLinesFragment(VertexOut in [[stage_in]],
                                   constant Uniforms& u [[buffer(0)]]) {
    const float speed     = 1.0;
    const float thickness = 0.01;
    const float3 line_color = float3(0.0, 1.0, 0.0);

    float t            = speed * u.time;
    float floor_t      = floor(t);
    float next_floor_t = floor_t + 1.0;
    float fract_t      = fract(t);

    float2 rand_vec = float2(
        random_sl(float2(floor_t, 0.0)),
        random_sl(float2(0.0, floor_t))
    );
    float2 next_rand_vec = float2(
        random_sl(float2(next_floor_t, 0.0)),
        random_sl(float2(0.0, next_floor_t))
    );

    float2 moving_point = mix(rand_vec, next_rand_vec, fract_t);
    float  color_mult   = point_to_color_sl(in.uv, moving_point, thickness);

    float3 color = color_mult * line_color;
    return float4(color, 1.0);
}
```

Helper functions are prefixed `_sl` to avoid name collisions with
future shaders in the same `.metal` file.

**Acceptance criteria:**
- Selecting Scan Lines shows two animated green scan lines on a black
  background.
- Lines jump to new positions smoothly over time.
- Dot style still works correctly.

---

## Out of scope

- Configurable line color, speed, or thickness via Settings UI.
- Independent X/Y bounds (`x_line_bounds`, `y_line_bounds`).
- Blending scan lines over a background texture.
