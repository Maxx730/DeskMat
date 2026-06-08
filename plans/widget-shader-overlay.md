# Plan: Widget Shader Overlay

## Goal

Add shader support to widget interiors — specifically, apply a shader to the layer below the text overlay in `CPUView`'s `ZStack`. Create a shared abstraction so any widget can adopt shaders without duplicating setup code.

---

## Background: Two Existing Shader Systems

| System | File | API | Applied to |
|---|---|---|---|
| Dock item shaders | `DockItemShader.swift` | SwiftUI `.colorEffect` / `.layerEffect` | Each dock icon |
| Reactive background | `ReactiveBackgroundView.swift` + `ReactiveShaders.metal` | Metal render pipeline via `NSViewRepresentable` | Full dock background |

Both systems already compile their shaders from `Shaders.metal` and `ReactiveShaders.metal`. The reactive background (`ReactiveBackgroundRepresentable`) is already a configurable struct that accepts `style`, `cornerRadius`, and `limitFPS`. It can be dropped into a SwiftUI `ZStack` as-is.

The dock item shader system (`DockItemShader` ViewModifier) reads `@AppStorage("visualEffect")` and `@AppStorage("dockItemShaderIntensity")` and can be applied to **any View** via `.dockItemShader()` — no changes needed.

---

## Design Decision

Two layers of shader support for widgets:

1. **Color/layer effects** — existing `DockItemShader` modifier applied directly to widget content (zero new code)
2. **Reactive background** — a thin `WidgetShaderBackground` wrapper around `ReactiveBackgroundRepresentable`, pre-configured for widget dimensions and with its own `@AppStorage` key so widgets can have a different reactive style than the dock

The CPU widget uses path (2) first since the waveform already provides the primary visual and a reactive shader behind it adds depth without competing. Path (1) can be applied on top as a pass-through color effect if desired.

---

## Phases

---

### Phase 1 — `WidgetShaderBackground` shared view

**Scope:** New file `WidgetShaderBackground.swift`

A thin SwiftUI wrapper around `ReactiveBackgroundRepresentable` that:
- Reads `@AppStorage("widgetShaderStyle")` (new key, separate from the dock's `reactiveStyle`)
- Defaults to `.none` so existing widgets are unaffected until opted in
- Exposes `cornerRadius` as a parameter so callers can match their widget's corner radius

```swift
struct WidgetShaderBackground: View {
    @AppStorage("widgetShaderStyle") private var style: ReactiveStyle = .none
    var cornerRadius: CGFloat = 10

    var body: some View {
        if style != .none {
            ReactiveBackgroundRepresentable(style: style,
                                            cornerRadius: cornerRadius,
                                            limitFPS: true)
        }
    }
}
```

**Why a separate `@AppStorage` key?**
The dock's reactive style is a full-bleed background. A widget shader sits inside a 64×64 pt cell — a style that looks good full-bleed may be overwhelming at small scale. Decoupling lets the user pick different styles for dock vs. widgets.

**Result:** Any widget can add `WidgetShaderBackground()` to the bottom of a `ZStack` to get reactive shader support with no further setup.

---

### Phase 2 — Wire `WidgetShaderBackground` into `CPUView`

**Scope:** `SystemWidget.swift` — `CPUView.body`

Insert `WidgetShaderBackground()` at the bottom of the `ZStack`, below `CPUGraphView`:

```swift
var body: some View {
    ZStack(alignment: .top) {
        WidgetShaderBackground()           // reactive shader, full panel
        CPUGraphView(history: history)     // waveform on top of shader
        VStack(spacing: 1) { ... }         // text overlay at top
    }
}
```

The waveform canvas uses a transparent background (no `.background()` call), so the reactive shader shows through the unfilled regions of the graph naturally.

**Corner radius:** `CPUView` is already clipped to `RoundedRectangle(cornerRadius: 10)` at the `SystemWidget` level, so `WidgetShaderBackground` passes `cornerRadius: 10` to match.

---

### Phase 3 — Settings UI entry point

**Scope:** `SettingsView.swift` — existing shader/appearance section

Add a `Picker` for `widgetShaderStyle` alongside the existing dock reactive style picker. Follow the same pattern already used for `reactiveStyle`:

```swift
Picker("Widget shader", selection: $widgetShaderStyle) {
    ForEach(ReactiveStyle.allCases) { style in
        Text(style.displayName).tag(style)
    }
}
```

This reuses `ReactiveStyle` directly — no new enum needed.

---

### Phase 4 — `.dockItemShader()` on CPUGraphView (optional colour pass)

**Scope:** `SystemWidget.swift` — `CPUGraphView` call site

The existing dock item shaders (`hueDrift`, `filmGrain`, `scanlineWiggle`, etc.) are colour/layer effects that remap existing pixels. Applying `.dockItemShader()` to `CPUGraphView` lets the waveform inherit the same visual effect the user has set for dock icons, creating visual cohesion:

```swift
CPUGraphView(history: history)
    .dockItemShader()
```

This is one line and zero new code — it only makes sense if the user enables a dock item shader. When `visualEffect == .none`, the modifier is a no-op.

**When to apply:** Only after Phase 2 is validated. Whether this is on by default or gated behind a setting is a product decision left for that phase.

---

## Files Changed

| File | Phase | Change |
|---|---|---|
| `WidgetShaderBackground.swift` | 1 | New file — `WidgetShaderBackground` view |
| `SystemWidget.swift` | 2 | Add `WidgetShaderBackground()` to `CPUView` ZStack |
| `SettingsView.swift` | 3 | Add widget shader style picker |
| `SystemWidget.swift` | 4 | Optionally apply `.dockItemShader()` to `CPUGraphView` |

---

## What Stays the Same

- `ReactiveBackgroundRepresentable` — used as-is, no changes
- `DockItemShader` — used as-is, no changes
- `Shaders.metal` / `ReactiveShaders.metal` — no changes
- `ReactiveStyle` enum — no changes
- Dock reactive background behaviour — completely unaffected
- RAM and Network widgets — unaffected until they opt in

---

## Open Questions

1. **Default style:** Should `widgetShaderStyle` default to `.none` (safe, explicit opt-in) or to one of the lighter styles like `topograph`? Recommend `.none` for now.
2. **Per-widget style:** This plan uses one global `widgetShaderStyle` key. If individual widgets should have different styles in the future, each widget would need its own `@AppStorage` key — leave as a follow-on plan.
3. **Performance:** Reactive shaders run a Metal render loop. At 64×64 pt the GPU cost is trivial, but `limitFPS: true` is passed as a precaution.
