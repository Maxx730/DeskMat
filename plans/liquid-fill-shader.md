# Liquid Fill Shader — Implementation Plan

Port the Godot "2D Liquid Fill Inside Sphere" shader to Metal and wire it
into the Reactive background system as a selectable style named **Liquid Fill**.

Source: https://godotshaders.com/shader/2d-liquid-fill-inside-sphere/
Original by Mirza Beig, Godot port by RuverQ.

---

## What the shader does

A sphere (circle) renders with a liquid fill that rises and falls. The liquid
surface is animated with two overlapping sine wave bands — a front wave and a
back wave — giving the illusion of a rounded meniscus with subtle depth. The
fill level is controlled by a single `fV` uniform (0–1). An outline ring marks
the sphere boundary.

---

## Adaptation strategy for the dock

The dock is a horizontal rounded rectangle, not a circle. Rather than letterbox
a sphere inside it, we adapt the effect to the rectangle:

- The liquid fills from the **bottom** of the dock upward.
- The wavey surface replaces the sphere's meniscus — same sine math, runs
  horizontally across the dock.
- A front and back wave layer provide the same depth illusion.
- The existing `roundedRectSDF` / `roundedRectAlpha` helpers handle masking to
  the dock's corner radius.
- Fill level oscillates gently with time (slow sine on `u.time`) so the dock
  looks alive even without interaction. When the mouse hovers, `indicatorOpacity`
  drives an additional swell — the liquid rises slightly on hover.

Color: a cool blue/teal (`float3(0.1, 0.55, 1.0)`) for the front wave,
slightly darker for the back wave, with a very subtle lighter tint at the
liquid surface edge.

---

## Godot → Metal translation notes

| Godot | Metal equivalent |
|---|---|
| `UV` | `in.uv` |
| `TIME` | `u.time` |
| `COLOR = vec4(...)` | `return float4(...)` |
| `step(a, b)` | `step(a, b)` (same signature in MSL) |
| `smoothstep(a, b, x)` | `smoothstep(a, b, x)` (same) |
| `clamp(x, a, b)` | `clamp(x, a, b)` (same) |
| `pow(x, n)` | `pow(x, n)` (same) |
| `PI` | `3.14159265` (literal) |
| sphere SDF `length(uv)` | `roundedRectSDF` for the dock shape |
| `fV` fill uniform | `fV` baked as `0.5` base + hover swell |

The UV remapping `UV / -0.10 + 1.25` in the original maps the 0–1 canvas UV
into a ±1 range centred on the sphere. For the dock rectangle we work directly
in 0–1 UV space with (0,0) at top-left (isFlipped = true), so Y=1 is the
bottom. No remapping needed — we compute fill position in Y directly.

---

## Phase 1 — Add `liquidFill` case to `ReactiveStyle`

**File:** `DeskMat/AppEnums.swift`

```swift
enum ReactiveStyle: String, CaseIterable {
    case dot        = "Dot"
    case lockOn     = "Lock-On"
    case liquidFill = "Liquid Fill"
    case ripple     = "Ripple"
    case glow       = "Glow"
}
```

**Acceptance criteria:**
- `"Liquid Fill"` appears in the Reactive Style dropdown in Settings.
- No rendering change yet.

---

## Phase 2 — Route `fragmentShaderName`

**File:** `DeskMat/ReactiveBackgroundView.swift`

```swift
var fragmentShaderName: String {
    switch reactiveStyle {
    case .dot:        return "dotFragment"
    case .lockOn:     return "lockOnFragment"
    case .liquidFill: return "liquidFillFragment"
    case .ripple:     return "rippleFragment"
    case .glow:       return "glowFragment"
    }
}
```

`reactiveStyle.didSet` already calls `rebuildPipeline()`, so the GPU pipeline
swaps automatically on style change.

**Acceptance criteria:**
- Switching to Liquid Fill calls `rebuildPipeline()` with `"liquidFillFragment"`.
- The dock renders nothing (pipeline miss) until Phase 3 adds the function.

---

## Phase 3 — Write `liquidFillFragment` in Metal

**File:** `DeskMat/ReactiveShaders.metal`

### Helper (add above the fragment function)

```metal
// Wave height at a given UV x position and time offset.
float liquidWave(float x, float t, float speed, float amp) {
    return sin((x * 2.0 + t * speed) * 2.0) * amp;
}
```

### Fragment

```metal
fragment float4 liquidFillFragment(VertexOut in [[stage_in]],
                                    constant Uniforms& u [[buffer(0)]]) {
    const float3 frontColor = float3(0.10, 0.55, 1.00);  // blue
    const float3 backColor  = frontColor * 0.65;
    const float3 bgColor    = frontColor * 0.04;

    float2 uv = in.uv;  // (0,0) top-left, (1,1) bottom-right

    // Rounded rect mask
    float alpha = roundedRectAlpha(uv, u.resolution, u.cornerRadius);

    // Fill level: base 0.5 + gentle idle oscillation + hover swell
    float idleOsc = sin(u.time * 0.8) * 0.03;
    float hoverSwell = u.indicatorOpacity * 0.12;
    float fP = 0.50 + idleOsc + hoverSwell;  // liquid top in UV Y (0=top, 1=bottom)

    // Wave envelope — stronger in the horizontal centre, fades toward edges
    float vB  = smoothstep(0.1, 0.9, sin(uv.x * 3.14159265)) - 0.3;

    // Front wave (travels right) and back wave (travels left)
    float fW = liquidWave(uv.x,  u.time, 2.0, 0.025) + vB * sin(u.time * 4.0) * 0.015;
    float bW = liquidWave(uv.x, -u.time, 2.0, 0.025) - vB * sin(u.time * 4.0) * 0.015;

    // Front amplitude oscillation
    float fA = sin(u.time * 4.0) * 0.02 * max(vB, 0.0);

    // In our flipped UV: uv.y increases downward, so liquid fills from bottom.
    // The liquid surface is at Y = fP; pixels with uv.y > fP are submerged.
    float frontFill = step((fA + fW) + fP, uv.y);
    float backFill  = step((-fA + bW) + fP, uv.y);

    // Specular highlight band just above the surface
    float surfaceY  = fP + fW;
    float highlight = smoothstep(0.012, 0.0, abs(uv.y - surfaceY)) * frontFill * 0.4;

    // Compose colour
    float3 color = bgColor
                 + frontFill  * frontColor
                 + clamp(backFill - frontFill, 0.0, 1.0) * backColor * 0.8
                 + highlight  * 1.0;

    return float4(color, alpha);
}
```

**Acceptance criteria:**
- Selecting Liquid Fill shows a blue liquid that fills roughly half the dock.
- The liquid surface waves gently up and down over time (idle oscillation).
- Hovering the mouse causes the liquid level to swell slightly higher.
- The liquid is masked to the dock's rounded corners.
- Dot and Lock-On styles still work correctly.

---

## Phase 4 — Polish (optional / post-ship)

Ideas to revisit after the base shader is working:

| Idea | Notes |
|---|---|
| Configurable color via Settings | Add `liquidFillColorHex` AppStorage key; pass as uniform |
| Configurable fill level | Expose `liquidFillLevel` (0–1) slider in Settings |
| Mouse X → fill direction | Liquid tilts toward mouse X position |
| Bubble particles | Small circles rising through the liquid |
| Surface foam line | Brighter 1–2px band exactly at the wave surface |

---

## Out of scope

- Physics-accurate fluid simulation.
- Rendering a circular sphere — the dock shape is rectangular.
- Interaction with the system Dock or other windows.
