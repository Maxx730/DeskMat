# Rainbow Outline Shader — Implementation Plan

Add a **Rainbow** reactive style: a 4 px thick rounded-rect outline drawn on
the inside edge of the dock that cycles through the full rainbow over time.
The fill is fully transparent — only the border is rendered.

---

## What the shader does

- Draws a 4 px border that traces the dock's rounded-corner shape.
- The border color cycles continuously through the HSV hue wheel (0 → 1 → 0…)
  driven by `u.time`.
- An optional travelling-rainbow variant offsets the hue by the pixel's angular
  position around the dock centre, so the color moves around the perimeter.
- The interior and the area outside the border are fully transparent.

---

## Shader strategy

### Border mask via SDF

The existing `roundedRectSDF` helper returns a signed distance value:
- **negative** — inside the shape
- **0** — exactly on the edge
- **positive** — outside the shape

A 4 px inset border occupies pixels where:

```
-borderWidth < sdf ≤ 0
```

Smooth anti-aliasing at both edges:

```metal
float outerA = smoothstep(0.0,  1.0, -sdf);           // fades at outer edge
float innerA = smoothstep(0.0,  1.0, sdf + borderWidth); // fades at inner edge
float borderMask = outerA * innerA;
```

### HSV → RGB

Standard formula inlined in the shader (no texture lookup needed):

```metal
float3 hsv2rgb(float h, float s, float v) {
    float3 rgb = clamp(abs(fmod(h * 6.0 + float3(0,4,2), 6.0) - 3.0) - 1.0,
                       0.0, 1.0);
    return v * mix(float3(1.0), rgb, s);
}
```

### Hue calculation

Two modes — pick one during implementation:

| Mode | Formula | Effect |
|---|---|---|
| Uniform | `hue = fract(u.time * 0.15)` | Whole border is one color; shifts slowly |
| Travelling | `hue = fract(angle / TAU + u.time * 0.15)` | Rainbow travels around the perimeter |

`angle = atan2(uv.y - 0.5, uv.x - 0.5)` gives the angular position of each
pixel around the dock centre. **Travelling rainbow is preferred** — it looks
more dynamic without any extra cost.

---

## Godot / Metal translation notes

| Concept | MSL |
|---|---|
| `fract(x)` | `fract(x)` |
| `mod(x, y)` | `fmod(x, y)` |
| `atan(y, x)` | `atan2(y, x)` |
| `PI * 2` | `6.28318530` (literal `TAU`) |
| SDF border mask | see above |

---

## Phase 1 — Add `rainbow` case to `ReactiveStyle`

**File:** `DeskMat/AppEnums.swift`

```swift
enum ReactiveStyle: String, CaseIterable {
    case lockOn     = "Lock-On"
    case liquidFill = "Liquid Fill"
    case rainbow    = "Rainbow"
}
```

**Acceptance criteria:**
- `"Rainbow"` appears in the Reactive Style dropdown in Settings.
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
    }
}
```

**Acceptance criteria:**
- Switching to Rainbow calls `rebuildPipeline()` with `"rainbowFragment"`.
- The dock renders nothing (pipeline miss) until Phase 3 adds the function.

---

## Phase 3 — Write `rainbowFragment` in Metal

**File:** `DeskMat/ReactiveShaders.metal`

### Helper (add above the fragment function)

```metal
float3 hsv2rgb(float h, float s, float v) {
    float3 rgb = clamp(abs(fmod(h * 6.0 + float3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0,
                       0.0, 1.0);
    return v * mix(float3(1.0), rgb, s);
}
```

### Fragment

```metal
fragment float4 rainbowFragment(VertexOut in [[stage_in]],
                                 constant Uniforms& u [[buffer(0)]]) {
    const float borderWidth = 4.0;   // px — border thickness
    const float speed       = 0.15;  // hue cycles per second

    float2 uv = in.uv;

    // Signed distance from rounded-rect edge (negative = inside)
    float sdf = roundedRectSDF(uv, u.resolution, u.cornerRadius);

    // Border mask: pixels in the 4 px inset band
    float outerA = smoothstep(1.0, 0.0, sdf);
    float innerA = smoothstep(0.0, 1.0, sdf + borderWidth);
    float mask   = outerA * innerA;

    if (mask < 0.001) { return float4(0.0); }  // early-out for transparent region

    // Travelling rainbow: hue varies by angle around the dock centre
    float angle  = atan2(uv.y - 0.5, uv.x - 0.5);
    float hue    = fract(angle / 6.28318530 + u.time * speed);

    float3 color = hsv2rgb(hue, 1.0, 1.0);

    return float4(color * mask, mask);
}
```

**Acceptance criteria:**
- Selecting Rainbow shows a fully transparent dock interior with a 4 px
  coloured outline following the dock's rounded corners.
- The color travels continuously around the perimeter.
- The outline respects the dock's corner radius.
- Lock-On and Liquid Fill styles still work correctly.

---

## Phase 4 — Polish (optional / post-ship)

| Idea | Notes |
|---|---|
| Configurable border width | `rainbowBorderWidth` AppStorage key; pass as uniform |
| Configurable speed | `rainbowSpeed` slider in Settings |
| Glow/bloom effect | Add a soft outer glow that matches the current hue |
| Pulse on hover | `indicatorOpacity` drives a brightness swell when mouse enters |
| Uniform-color mode | Toggle to disable travelling; whole border one hue at a time |

---

## Out of scope

- Physics-accurate color diffusion.
- Rendering an outline outside the dock bounds (always inset).
- Interaction with the system Dock or other windows.
