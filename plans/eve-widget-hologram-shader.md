# Eve Widget Hologram Shader

Add a CRT-style hologram effect to the Eve widget using a Metal shader. Includes a refactor of the existing shader plumbing to extract a reusable `WidgetShaderModifier` that any future widget can adopt.

---

## Background

`DockItemShader` already solves the core problem — `TimelineView` at the right frame rate, `ShaderApplication` dispatch, `applyShader` helper — but it is tightly coupled to the global `visualEffect` setting and the dock item context. Two pieces are worth extracting:

1. `ShaderApplication` enum + `applyShader` view extension (currently private inside `DockItemShader.swift`)
2. The `TimelineView` + geometry tracking loop that every animated shader needs

---

## Phase 1 — Refactor: `WidgetShaderModifier`

**New file: `DeskMat/WidgetShaderModifier.swift`**

Extract the shared plumbing into a reusable protocol + generic modifier:

```swift
// Describes the update cadence of a shader
enum WidgetShaderRate {
    case animation              // full display refresh — for motion effects
    case fps(Double)            // periodic — e.g. 24 for grain, 10 for slow drift
}

// A self-contained shader effect a widget can adopt
protocol WidgetShaderEffect {
    var rate: WidgetShaderRate { get }
    func shader(elapsed: TimeInterval, size: CGSize) -> ShaderApplication
}

// Generic ViewModifier — wraps the TimelineView + geometry tracking boilerplate
struct WidgetShaderModifier<Effect: WidgetShaderEffect>: ViewModifier {
    let effect: Effect
    @State private var viewSize: CGSize = .zero
    private let startDate = Date.now

    func body(content: Content) -> some View { ... }
}

extension View {
    func widgetShader<E: WidgetShaderEffect>(_ effect: E) -> some View {
        modifier(WidgetShaderModifier(effect: effect))
    }
}
```

**Move `ShaderApplication` + `applyShader`** out of `DockItemShader.swift` into this new file so both `DockItemShader` and `WidgetShaderModifier` can share them. `DockItemShader` imports nothing new — it just stops re-declaring the private types.

No behaviour change — this phase is pure refactor. `DockItemShader` is updated to use the now-shared `ShaderApplication` type.

---

## Phase 2 — Metal shader: `eveHologram`

**Add to `Shaders.metal`:**

```metal
[[stitchable]] half4 eveHologram(
    float2 position,
    SwiftUI::Layer layer,
    float time,
    float intensity,
    float viewWidth,
    float viewHeight,
    float tintR, float tintG, float tintB   // faction color for chroma tint
)
```

Effect layers (all scaled by `intensity`):

1. **Scan lines** — alternating dark/transparent horizontal bands at ~80 lines per widget height. Each band is a smooth `smoothstep` fade so they aren't harsh pixel edges.
2. **Sweep band** — a single brighter horizontal band that scrolls top→bottom in a loop (~4 s period). Adds the "active hologram" feel.
3. **Chromatic aberration** — sample the red channel 1–2 px left, blue channel 1–2 px right. Gives the colour-fringing of a CRT phosphor.
4. **Faction tint** — lerp dark areas slightly toward the faction color (`tintR/G/B`). Bright areas stay white so text remains readable.
5. **Vignette** — darken corners with a radial falloff. Subtle — 10–15% max.
6. **Noise flicker** — low-amplitude per-frame noise (`fract(sin(...) * time)`) to simulate electron beam instability.

The shader uses `.layerEffect` (needs to sample offset positions for aberration). `maxSampleOffset` width ~2 pt covers the aberration sample range.

---

## Phase 3 — `EveHologramEffect` + wire-up

**New file: `DeskMat/EveHologramEffect.swift`**

```swift
struct EveHologramEffect: WidgetShaderEffect {
    let intensity: Float
    let tint: Color       // derived from EveWidgetTheme.color

    var rate: WidgetShaderRate { .animation }

    func shader(elapsed: TimeInterval, size: CGSize) -> ShaderApplication {
        let rgb = tint.resolvedRGB   // small Color helper → (Float, Float, Float)
        return .layer(
            ShaderLibrary.eveHologram(
                .float(Float(elapsed)),
                .float(intensity),
                .float(Float(size.width)),
                .float(Float(size.height)),
                .float(rgb.r), .float(rgb.g), .float(rgb.b)
            ),
            maxSampleOffset: CGSize(width: 2, height: 0)
        )
    }
}
```

**In `EveWidget.swift`**, apply after `DockWidget`:

```swift
DockWidget(...) { ... }
    .widgetShader(EveHologramEffect(
        intensity: theme == .auto ? 0 : 0.6,
        tint: theme.color ?? .white
    ))
```

Setting `intensity: 0` for `.auto` disables the effect with zero overhead (the shader short-circuits at intensity == 0) — no conditional modifier needed.

**Helper `Color.resolvedRGB`** — a small extension that decomposes a SwiftUI `Color` into `(r: Float, g: Float, b: Float)` via `NSColor` resolution. Lives in `ColorUtils.swift` alongside existing color helpers.

---

## Notes

- Phase 1 is purely structural — no visual change, safe to ship independently.
- Phase 3's `intensity: 0` short-circuit means the shader is compiled and bound but does nothing when auto is selected — this is the same pattern used by `DockItemShader` for `.none`.
- If the effect is too heavy on low-end Macs, drop the rate from `.animation` to `.fps(30)` in `EveHologramEffect.rate` — the sweep band is the only thing that truly needs full refresh rate.
- Future widgets (RAM chip, CPU waveform overlay, etc.) adopt the pattern by conforming to `WidgetShaderEffect` — no changes to the modifier or Metal file needed.
