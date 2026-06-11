# Shader System Unification

Consolidate the three shader systems in DeskMat into a cleaner, more consistent architecture. Two of the three (dock item shaders and widget shaders) are already the same idea and can share a single implementation. The third (reactive backgrounds) is architecturally distinct and stays separate, but gets clearer boundaries.

---

## Current State

Three shader systems coexist:

| System | File(s) | API | Used on |
|---|---|---|---|
| Dock item shaders | `DockItemShader.swift` | SwiftUI `.layerEffect` / `.colorEffect` | Every dock icon |
| Widget shaders | `WidgetShaderModifier.swift` | SwiftUI `.layerEffect` / `.colorEffect` | Eve widget (hologram) |
| Reactive backgrounds | `ReactiveBackgroundView.swift` | AppKit `MTKView` + raw Metal | Widget background fills |

Systems 1 and 2 are the same mechanism — `TimelineView` at a chosen frame rate, geometry tracking, `ShaderApplication` dispatch — but `DockItemShader` still has its own hand-rolled version of that loop rather than using `WidgetShaderModifier`.

System 3 **cannot** be merged into the SwiftUI shader API. It requires raw Metal command buffers (multi-pass rendering: main → edge highlight → corner mask), vertex shaders, mouse position uniforms, and `MTKView`'s render loop. SwiftUI `.layerEffect` has none of these. It stays as-is but gets clearer documentation.

---

## Phase 1 — Refactor `DockItemShader` to use `WidgetShaderEffect`

`DockItemShader` currently re-implements the same `TimelineView` + geometry + `applyShader` loop that `WidgetShaderModifier` owns. The goal is to delete that duplication.

**Create `DockVisualEffect.swift`** — a `WidgetShaderEffect` conformance that wraps the existing visual effect dispatch:

```swift
struct DockVisualEffect: WidgetShaderEffect {
    let effect:    VisualEffect
    let intensity: Double
    let viewSize:  CGSize   // passed in from DockItemShader's geometry observer

    var isEnabled: Bool { effect != .none }

    var rate: WidgetShaderRate {
        switch effect {
        case .scanlineWiggle, .heatShimmer: return .animation
        case .filmGrain, .oldFilm:          return .fps(24)
        case .hueDrift:                     return .fps(10)
        case .pixelate, .softBloom, .none:  return .fps(2)
        }
    }

    func shader(elapsed: TimeInterval, size: CGSize) -> ShaderApplication { ... }
}
```

`DockItemShader` becomes a thin wrapper:

```swift
struct DockItemShader: ViewModifier {
    @Environment(LicenseManager.self) private var entitlements
    @AppStorage("visualEffect")             private var visualEffect: VisualEffect = .none
    @AppStorage("dockItemShaderIntensity")  private var intensity = 0.5

    func body(content: Content) -> some View {
        content.widgetShader(DockVisualEffect(
            effect:    entitlements.isPro ? visualEffect : .none,
            intensity: intensity
        ))
    }
}
```

`WidgetShaderModifier` handles the `TimelineView`, geometry, `isEnabled` guard — `DockItemShader` provides none of that itself anymore.

**Note on `viewSize`:** `DockVisualEffect.shader(elapsed:size:)` already receives `size` from `WidgetShaderModifier`'s geometry observer — no need to pass it separately. Remove the bespoke geometry tracking from `DockItemShader`.

---

## Phase 2 — Reorganize Metal files

Currently `Shaders.metal` contains both SwiftUI-compatible shaders (used via `ShaderLibrary`) and `ReactiveShaders.metal` contains AppKit Metal shaders (used via `MTLLibrary`). The distinction is not obvious from the file names.

Rename and reorganize:

| Old | New | Contains |
|---|---|---|
| `Shaders.metal` | `SwiftUIShaders.metal` | All shaders called via `ShaderLibrary.*` — scanline wiggle, bloom, film grain, heat shimmer, old film, shine glint, hue drift, eve hologram |
| `ReactiveShaders.metal` | `ReactiveShaders.metal` | Unchanged — vertex + fragment shaders for the AppKit MTKView pipeline |

Add a header comment block to each file explaining which API calls it and why they are separate.

No behaviour change — purely organizational.

---

## Phase 3 — Document the ReactiveBackground boundary

Add a `SHADER_SYSTEMS.md` in `DeskMat/` (or as a comment block at the top of `ReactiveBackgroundView.swift`) that clearly states why the three systems exist and what each one owns, so future contributors don't try to merge them incorrectly.

Key points to capture:
- SwiftUI shaders (`SwiftUIShaders.metal`) — post-process overlays on rendered SwiftUI views. One Metal function per effect, called via `ShaderLibrary`. No vertex stage, no multi-pass, no mouse input.
- Reactive backgrounds (`ReactiveShaders.metal` + `ReactiveBackgroundView`) — fullscreen background fills with mouse-reactive uniforms, edge highlight + corner mask multi-pass pipeline, AppKit mouse tracking. Cannot be expressed as a SwiftUI shader.
- The two SwiftUI shader consumers (`DockItemShader`, `WidgetShaderModifier`) share one implementation after Phase 1.

---

## What does NOT change

- `ReactiveBackgroundView`, `ReactiveBackgroundRepresentable`, `WidgetShaderBackground` — no changes, already clean
- `WidgetShaderEffect` protocol, `WidgetShaderModifier`, `EveHologramEffect` — no changes
- All existing behaviour and visual output
