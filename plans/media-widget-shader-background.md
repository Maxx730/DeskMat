# Media Widget — Metal Shader Background

Replace the solid-colour `backgroundColor` on `DockWidget` with a Metal shader
background driven by `ReactiveBackgroundView`. Phase 1 renders the average
album-art colour; the architecture is in place to add animated effects later
without touching the SwiftUI layer.

---

## Why Metal instead of SwiftUI Color

`DockWidget(backgroundColor:)` renders a plain `RoundedRectangle.fill()`.
A Metal background opens the door to:
- Animated gradients or pulse effects keyed to playback state
- Future multi-pass effects (glow, noise, colour transitions) with no Swift changes
- Mouse-reactive effects reusing the existing `NSTrackingArea` infrastructure

All of that is doable by editing only the fragment shader once this architecture
is in place.

---

## How it fits into the existing shader systems

DeskMat has two shader systems (documented at the top of `ReactiveBackgroundView.swift`).
This plan uses **System 2** — the raw Metal MTKView pipeline — because System 1
(SwiftUI `.layerEffect` / `.colorEffect`) does not support a continuous render loop
or the multi-pass pipeline the base class already provides.

The new `MediaBackgroundView` is a subclass of `ReactiveBackgroundView`. It reuses:
- The three-pass pipeline (main → edge highlight → corner mask)
- The `configureEncoder` override hook for injecting per-frame data
- `NSTrackingArea`, FPS limiting, and `ReactiveUniforms`

The only new pieces are a single fragment function and the subclass file.

---

## Architecture overview

```
MediaControlWidget
  └── DockWidget(backgroundColor: nil)   ← remove SwiftUI colour fill
        └── ZStack
              ├── MediaBackgroundRepresentable(color:cornerRadius:)   ← NEW bottom layer
              └── trackView(track)                                     ← unchanged
```

---

## Phase 1 — New ReactiveStyle case + Metal fragment

### 1a — `AppEnums.swift`: add `.media` case

```swift
enum ReactiveStyle: String, CaseIterable {
    // existing cases …
    case media   // internal — not shown in the settings reactive-background picker
}
```

Add `.media` to the `noEdgeHighlight` set in `ReactiveBackgroundView.draw(in:)` if
a plain solid fill with no rim is preferred; leave it out to keep the subtle edge
highlight that all other styles receive. Either decision is reversible.

### 1b — `ReactiveBackgroundView.swift`: route fragment name

Add one case to `fragmentShaderName`:

```swift
case .media: return "mediaBackgroundFragment"
```

### 1c — `ReactiveShaders.metal`: new fragment function

```metal
// buffer(0) = Uniforms      — same struct every reactive shader receives
// buffer(1) = float3 color  — linear RGB, pushed per-frame by MediaBackgroundView

fragment float4 mediaBackgroundFragment(VertexOut        in      [[stage_in]],
                                        constant Uniforms &u     [[buffer(0)]],
                                        constant float3   &color [[buffer(1)]]) {
    float alpha = roundedRectAlpha(in.uv, u.resolution, u.cornerRadius);
    return float4(color, alpha);
}
```

`roundedRectAlpha` already exists in the file and handles corner SDF +
anti-aliasing — no new helper needed.

---

## Phase 2 — MediaBackgroundView subclass

**New file:** `DeskMat/Widgets/MediaControl/MediaBackgroundView.swift`

```swift
import AppKit
import Metal
import SwiftUI

/// ReactiveBackgroundView subclass that renders a solid colour via Metal.
/// The colour is pushed to the shader every frame via buffer(1) — no pipeline
/// rebuild is needed when the colour changes.
final class MediaBackgroundView: ReactiveBackgroundView {

    var color: NSColor = .systemBlue

    override var fragmentShaderName: String { "mediaBackgroundFragment" }

    override func configureEncoder(_ encoder: MTLRenderCommandEncoder,
                                   uniforms: inout ReactiveUniforms) {
        var rgb = color.linearRGB
        encoder.setFragmentBytes(&rgb,
                                 length: MemoryLayout<SIMD3<Float>>.stride,
                                 index: 1)
    }
}

// MARK: - SwiftUI wrapper

struct MediaBackgroundRepresentable: NSViewRepresentable {
    let color:        NSColor
    let cornerRadius: CGFloat

    func makeNSView(context: Context) -> MediaBackgroundView {
        let v = MediaBackgroundView()
        v.reactiveStyle = .media   // triggers pipeline build in base class
        v.cornerRadius  = cornerRadius
        v.limitFPS      = true
        return v
    }

    func updateNSView(_ nsView: MediaBackgroundView, context: Context) {
        nsView.color        = color
        nsView.cornerRadius = cornerRadius
    }
}

// MARK: - NSColor helpers

private extension NSColor {
    /// Converts to device RGB and returns a Metal-ready SIMD3<Float>.
    var linearRGB: SIMD3<Float> {
        guard let c = usingColorSpace(.deviceRGB) else { return SIMD3(0.2, 0.4, 0.9) }
        return SIMD3<Float>(Float(c.redComponent),
                            Float(c.greenComponent),
                            Float(c.blueComponent))
    }
}
```

---

## Phase 3 — Wire into MediaControlWidget

**File:** `DeskMat/Widgets/MediaControl/MediaControlWidget.swift`

Three changes:

**1.** Change DockWidget to `backgroundColor: nil` so it draws only its glass border
(the shader fills the interior):

```swift
DockWidget(cells: Self.cellCount, backgroundColor: nil) { … }
```

**2.** Add `MediaBackgroundRepresentable` as the bottom layer of the `trackView` ZStack:

```swift
private func trackView(_ track: NowPlayingInfo) -> some View {
    ZStack {
        MediaBackgroundRepresentable(
            color:        media.artworkColor.map { NSColor($0) } ?? .systemBlue,
            cornerRadius: 10
        )

        // Info layer (unchanged) …
        // Controls layer (unchanged) …
    }
    .animation(.easeInOut(duration: 0.18), value: isHovering)
}
```

**3.** Apply the same background in `nothingPlayingView` so the widget has a
consistent Metal-rendered background in all states:

```swift
private var nothingPlayingView: some View {
    ZStack {
        MediaBackgroundRepresentable(color: .systemBlue, cornerRadius: 10)
        VStack(spacing: 4) { … }
    }
}
```

---

## Edge cases

| Case | Handling |
|---|---|
| `artworkColor == nil` (fetch in-flight or nothing playing) | Representable passes `.systemBlue` |
| Metal device unavailable | `setup()` in base class guards on `MTLCreateSystemDefaultDevice()` — returns without adding MTKView; DockWidget's glass background shows |
| Widget resizes | `ReactiveBackgroundView.layout()` already updates `metalView.frame` and `cachedResolution` |
| `.media` in settings picker | `ReactiveStyle.media` must be excluded from any UI that enumerates all cases (Settings reactive picker). Add a `static var userFacing: [ReactiveStyle]` filter if needed |

---

## Acceptance criteria

- [ ] Widget background renders the average album-art colour via the Metal shader
- [ ] Colour updates within one render frame when `media.artworkColor` changes
- [ ] Falls back to blue when no artwork colour is available
- [ ] Corner masking matches the existing 10 pt widget corner radius
- [ ] No regression in other widgets using `ReactiveBackgroundView`
- [ ] `ReactiveStyle.media` does not appear in the Settings reactive-background picker
- [ ] `MediaBackgroundView` compiles with no warnings
