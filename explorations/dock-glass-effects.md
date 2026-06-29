# Exploration: Glass Effects in the Dock

## Overview

This document surveys every API available for producing glass/frosted-glass visuals in the dock — from the system blur compositor to custom Metal shaders — and maps each against specific features that could be built. The goal is to understand the design space before committing to an implementation.

The dock panel is already well-suited for glass: `DeskMatPanel` is borderless, `isOpaque = false`, and `backgroundColor = .clear`, which means the compositor routes desktop content through the window before compositing it — the essential prerequisite for any blur-behind effect.

---

## APIs Available

### 1. NSVisualEffectView (AppKit — Already Partially Used)

`NSVisualEffectView` is the AppKit compositor surface that drives every piece of frosted glass on macOS. It hooks into the window server's private blur pass and composites a desaturated, blurred snapshot of what's behind the window. DeskMat already uses it via `VisualEffectBackground` in [DeskMatPanel.swift](../DeskMat/App/DeskMatPanel.swift) for the `DockBackground.system` case in [ContentView.swift](../DeskMat/App/ContentView.swift).

**Blending modes:**

| Mode | Behaviour | Requires |
|---|---|---|
| `.behindWindow` | Blurs content behind the entire panel (wallpaper, other windows) | `panel.isOpaque = false`, `panel.backgroundColor = .clear` ✓ |
| `.withinWindow` | Blurs content within the same window only | Always available, rarely useful for a dock |

**Materials — 14 system-defined vibes:**

| Material | Visual character |
|---|---|
| `.hudWindow` | Current default. Dark semi-opaque, strong blur. |
| `.popover` | Light, high-contrast blur. Feels like a system popover. |
| `.menu` | Similar to `.popover`, used by menu bar items. |
| `.sidebar` | Subtle, light blur — Finder sidebar style. |
| `.titlebar` | Slightly less blur, matches window chrome. |
| `.sheet` | Sheet-modal grey tone. |
| `.contentBackground` | Near-white matte, minimal blur. |
| `.underWindowBackground` | Very transparent — nearly invisible. |
| `.underPageBackground` | Linen-like texture (mostly irrelevant today). |
| `.selection` | Highlight blue/grey. Semantic rather than textural. |
| `.headerView` | Table header band style. |
| `.windowBackground` | Full-window standard background. |
| `.toolTip` | Yellow-tinted tooltip. Semantic only. |
| `.fullScreenUI` | Dark translucent, optimized for full-screen mode. |

**Other configurable properties:**

- `state`: `.active` forces blur on even when the window is inactive. `.followsWindowActiveState` (default) dims blur when the app is in the background.
- `layer?.cornerRadius`: Works — the existing `VisualEffectBackground` already applies a 16pt radius.
- `layer?.masksToBounds = true`: Required for the corner radius to clip the blur surface.
- No public API for tint color on the blur itself. You can overlay a semi-transparent color view on top of the `NSVisualEffectView` to tint it.
- `NSVibrancyEffect` (an `NSAppearance` override placed on child views) makes text/icons adapt to the material beneath, appearing "embedded" in the glass.

**Integration point:** `VisualEffectBackground` in [DeskMatPanel.swift](../DeskMat/App/DeskMatPanel.swift) wraps `NSVisualEffectView` as an `NSViewRepresentable`. It's already wired into `ContentView`'s `.background` switch for `.system`. Extending this to expose the material as a user setting is a small change.

---

### 2. SwiftUI Materials (`.ultraThinMaterial`, etc.)

SwiftUI ships five material tokens that each resolve to an `NSVisualEffectView` with a specific material:

| SwiftUI Token | Approximate AppKit Material |
|---|---|
| `.ultraThinMaterial` | Something between `.underWindowBackground` and `.hudWindow` |
| `.thinMaterial` | ~ `.popover` |
| `.regularMaterial` | ~ `.popover` (slightly more opaque) |
| `.thickMaterial` | ~ `.hudWindow` |
| `.ultraThickMaterial` | Near-opaque, very heavy blur |

These can be applied directly in SwiftUI:

```swift
RoundedRectangle(cornerRadius: 10)
    .fill(.ultraThinMaterial)
```

Or as a `.background()` modifier:

```swift
someView.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
```

Because the dock panel is already transparent, SwiftUI materials pick up the wallpaper through `.behindWindow` blending automatically — no extra NSView configuration needed.

**Key advantage over raw `NSVisualEffectView`:** Materials compose naturally with SwiftUI's view tree. You can apply a different material to each widget or icon individually without any `NSViewRepresentable` boilerplate.

**macOS version requirement:** All five tokens are available since macOS 12 (Monterey).

---

### 3. Metal Shaders (Already Integrated)

DeskMat already has a Metal shader pipeline via `DockVisualEffect` / `DockItemShader`. The existing shaders use SwiftUI's `.colorEffect()` and `.layerEffect()` entry points from the `ShaderLibrary`.

**What's possible in Metal for glass:**

#### `.layerEffect()` — samples the view's pixel neighbourhood
The most relevant type for glass. Each invocation receives the view's own rendered pixels (not the desktop behind) and can sample within `maxSampleOffset` pixels. This enables:

- **Box blur / approximated Gaussian blur** — collect a grid of samples around each pixel and average them. Limited to the `maxSampleOffset` radius you declare. A 10px blur radius is cheap; a 40px radius is expensive.
- **Lens distortion / refraction** — displace sample coordinates using a radial warp function. Gives a convex or concave glass-lens feel.
- **Specular highlight** — add a white gradient stripe without touching the background. Cheaper than any blur.
- **Frost/noise texture** — overlay procedural noise to simulate an etched-glass surface.

#### `.colorEffect()` — per-pixel only, no neighbours
Suitable for:
- Glass tint (hue rotation, saturation boost)
- Chromatic aberration on icon edges
- Iridescent shift on hover

#### Limitation
Metal shaders operate on the view's own rendered pixels — not on the desktop content behind the panel. You cannot replicate `NSVisualEffectView`'s "see through to the wallpaper" with a shader alone. For a true frosted-glass look, `NSVisualEffectView` handles the blur-behind portion, and a Metal shader can handle surface details (specular, grain, distortion) layered on top.

---

### 4. CoreImage Filters (CIFilter)

`CIFilter` gives access to ~200 image processing filters including Gaussian blur, bloom, gloom, crystallize, pixelate, and more.

Applied to a live view in AppKit via `NSView.backgroundFilters` or `NSView.contentFilters`:

```swift
let blur = CIFilter(name: "CIGaussianBlur")!
blur.setValue(8.0, forKey: kCIInputRadiusKey)
someNSView.backgroundFilters = [blur]
```

**Key points:**
- `backgroundFilters` processes whatever is *behind* the view in the same window. It does **not** capture desktop content behind the panel (that's `NSVisualEffectView`'s job). Most useful for blurring dock content that appears behind other dock content.
- `contentFilters` processes the view's own rendered output — similar to `.layerEffect()` in Metal but with the full CoreImage filter catalogue.
- `NSView.compositingFilter` composites the view against its superview using a blend mode (multiply, screen, overlay, etc.).
- These work from AppKit only; you access them via `NSViewRepresentable` or a custom `NSView` subclass.

---

### 5. `.visualEffect` SwiftUI Modifier (macOS 14+)

```swift
someView.visualEffect { content, geometryProxy in
    content
        .blur(radius: 4)
        .saturation(1.4)
        .opacity(0.9)
}
```

This modifier is geometry-aware and runs in the layout phase. It is NOT the same as `NSVisualEffectView` — `.blur()` here blurs the view's own rendered pixels (SwiftUI uses Core Image under the hood). Useful for applying blur to the content *within* the dock while the background blur remains handled by `NSVisualEffectView`. macOS 14 / iOS 17 minimum.

---

## What Could Be Built

### A. Material Picker — Expose the 5 SwiftUI materials as a user setting

The simplest improvement. Replace the current hardcoded `.hudWindow` material with a `@AppStorage` enum that maps to one of the five SwiftUI material tokens. The background switch in `ContentView` already has a `.system` case — this would be a sub-option under it.

**Effort:** Low. No new architecture. Just a new enum value + a picker in Settings.
**Where:** [ContentView.swift](../DeskMat/App/ContentView.swift) `.background {}` block, [DeskMatPanel.swift](../DeskMat/App/DeskMatPanel.swift) `VisualEffectBackground`.

---

### B. Per-Item Glass Pill Background

Instead of (or in addition to) the dock-wide background, each icon and widget slot gets its own individual frosted glass container — a pill or rounded rectangle behind each icon. When the dock background is `.transparent`, individual glass pills would float directly against the wallpaper.

```swift
// Conceptually, in AppShortcutButton:
iconView
    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
```

This is how the macOS Control Center tiles look. It gives a more segmented, "each item is its own glass chip" aesthetic vs. the current unified slab.

**Effort:** Low–Medium. SwiftUI materials compose cleanly. The main work is deciding whether this replaces `showIconBackground` or co-exists with it, and wiring the setting.
**Where:** [AppShortcutButton.swift](../DeskMat/Dock/AppShortcutButton.swift) icon ZStack, [DockWidget.swift](../DeskMat/Dock/DockWidget.swift).

---

### C. Tinted Glass — Color Overlay on NSVisualEffectView

`NSVisualEffectView` doesn't have a `tintColor` property. The way to tint it is to overlay a semi-transparent `Color` view on top of the `VisualEffectBackground`. Combined with the existing `dockBackgroundColorHex` setting, you could offer "tinted glass" as a new `DockBackground` case — blur behind, tinted on top.

```swift
// In ContentView background switch:
case .tintedGlass:
    ZStack {
        VisualEffectBackground()
        RoundedRectangle(cornerRadius: dockCornerRadius)
            .fill(ColorUtils.fromHex(dockBackgroundColorHex).opacity(0.25))
    }
```

**Effort:** Very low. One new enum case, one new `ZStack` background layer.
**Where:** [AppEnums.swift](../DeskMat/Core/AppEnums.swift) `DockBackground`, [ContentView.swift](../DeskMat/App/ContentView.swift).

---

### D. Metal Specular Highlight Shader

A thin white-to-transparent gradient arc painted across the top of the dock background to simulate a physical glass surface catching light. This is a purely additive cosmetic layer — no blur needed, extremely cheap.

As a `.layerEffect()` shader, it would read the current pixel's normalized Y position and add white luminance near the top edge, falling off with a smooth curve. It could animate subtly on hover.

```metal
// Pseudocode for the Metal kernel
[[ stitchable ]] half4 glassHighlight(float2 position, SwiftUI::Layer layer, float2 size, float intensity) {
    half4 pixel = layer.sample(position);
    float t = position.y / size.y;
    float highlight = smoothstep(0.0, 0.35, 1.0 - t) * intensity * 0.35;
    return pixel + half4(highlight, highlight, highlight, 0.0);
}
```

**Effort:** Low. Fits naturally alongside the existing `DockVisualEffect` / `VisualEffect` shader pipeline.
**Where:** New case in `VisualEffect` enum in [AppEnums.swift](../DeskMat/Core/AppEnums.swift), new shader in the Metal shader file, new case in [DockVisualEffect.swift](../DeskMat/Shaders/DockVisualEffect.swift).

---

### E. Lens Distortion Shader on Hover

When the cursor hovers over a dock icon, apply a radial warp to the icon's pixels — as if the icon is sitting behind a convex glass lens. Magnification at center, slight distortion at edges.

This would live in `HoverAnimation` as a new case `.lens`, using a `.layerEffect()` shader applied to the icon `ZStack`.

```metal
[[ stitchable ]] half4 lensDistort(float2 pos, SwiftUI::Layer layer, float2 size, float strength) {
    float2 center = size * 0.5;
    float2 offset = (pos - center) / center;
    float r = length(offset);
    float2 warped = center + (offset * (1.0 + strength * r * r)) * center;
    return layer.sample(warped);
}
```

**Effort:** Medium. Requires a new shader + integration with the hover state already tracked in `AppShortcutButton`. The `maxSampleOffset` needs to be set large enough to cover the distortion range.
**Where:** New `HoverAnimation` case, new Metal kernel, applied in [AppShortcutButton.swift](../DeskMat/Dock/AppShortcutButton.swift).

---

### F. Frosted Glass Widget Containers

Each widget (`WeatherWidget`, `ClockWidget`, etc.) uses `DockWidget` as its container, which currently draws either a solid color or nothing. Adding a `GlassDockWidget` variant — or a new `backgroundColor` preset — that uses `.ultraThinMaterial` would give each widget a distinct frosted pane while the dock background is transparent.

```swift
// In DockWidget:
case .glass:
    RoundedRectangle(cornerRadius: 10)
        .fill(.ultraThinMaterial)
        .stroke(Color.white.opacity(0.15), lineWidth: 1)
```

**Effort:** Low. `DockWidget` already accepts an optional `backgroundColor`; a new init parameter or enum value would cover this without breaking existing call sites.
**Where:** [DockWidget.swift](../DeskMat/Dock/DockWidget.swift).

---

### G. Vibrancy on Labels and Icons

`NSVibrancyEffect` (AppKit) / `.vibrancy` (SwiftUI via `NSViewRepresentable`) makes a view's content adapt to the material beneath it — text reads as "etched into" the glass rather than floating on top. This is most impactful on dock labels and widget text when the background is glass.

In SwiftUI there's no direct `.vibrancy()` modifier, but you can wrap labels in an `NSHostingView` inside an `NSVisualEffectView` with a `NSVibrancyEffect` applied. The `VibrantLabel` view would be a small `NSViewRepresentable`.

**Effort:** Medium. Requires AppKit wrapping but no architectural change. Most valuable paired with feature A or C (glass backgrounds with readable text over wallpaper).
**Where:** New `VibrantLabel` NSViewRepresentable, adopted in [AppShortcutButton.swift](../DeskMat/Dock/AppShortcutButton.swift) for labels when glass background is active.

---

## Constraints and Notes

- **`NSVisualEffectView` + `.behindWindow` only works when the panel is non-opaque.** The panel is already configured correctly (`isOpaque = false`, `backgroundColor = .clear`), so this works out of the box.
- **Metal `.layerEffect()` cannot sample desktop content behind the panel.** It samples the view's own pixels. Only `NSVisualEffectView` can reach through to the compositor's behind-window buffer.
- **Shadow interaction:** `panel.hasShadow` is currently toggled off for non-system backgrounds (`updatePanelShadow()` in [AppDelegate+Panel.swift](../DeskMat/App/AppDelegate+Panel.swift)). Glass backgrounds (tinted glass, glass pills) should also set `hasShadow = true` for realism.
- **Dark/light mode:** `NSVisualEffectView` materials automatically adapt. The `.system` and `.thinMaterial` families look good in both modes. Custom color tints need to be tested in both appearances.
- **Performance:** `NSVisualEffectView` with `.behindWindow` is GPU-composited by the window server — essentially free from the app's perspective. Metal shaders add cost proportional to shader complexity and frame rate (`rate` in `DockVisualEffect`). Specular highlights at `.fps(2)` are negligible.
- **App Sandbox / entitlements:** No special entitlements needed for any of the above. `NSVisualEffectView` and SwiftUI materials are fully public API.

---

## Recommended Starting Point

The highest impact / lowest effort path:

1. **C (Tinted Glass)** — one new enum case, near-zero code. Immediately unlocks a class of dock aesthetics.
2. **A (Material Picker)** — exposes `.thinMaterial`, `.regularMaterial`, etc. as user options. Small settings addition.
3. **D (Specular Highlight Shader)** — adds physical glass realism on top of the blur with a cheap Metal shader that fits directly into the existing `VisualEffect` pipeline.

Features B, E, F, G are each self-contained and can follow independently.
