# Animated Edge Effect for Dock

## Goal
Add a pulsing animated stroke around the outer edge of the dock that transitions between gray and white.

## Current State
- The dock's outer frame has **no explicit stroke/border** — its edge is defined purely by `VisualEffectBackground` (a `NSVisualEffectView` with `.hudWindow` material and 16pt corner radius)
- The panel itself is borderless (`styleMask: [.borderless, .nonactivatingPanel]`)
- ContentView's `HStack` has 10pt padding but no overlay border
- Individual widgets inside have their own dual-stroke borders (in `DockWidget.swift`), but the dock container does not

## Approach
Add a `RoundedRectangle` stroke overlay to the `HStack` in `ContentView.swift` that animates its color between gray and white using a repeating animation.

### Implementation

**File: `DeskMat/DeskMat/ContentView.swift`**

1. Add a `@State private var edgeGlow: Bool = false` toggle that drives the animation
2. Add an `.overlay` with a `RoundedRectangle(cornerRadius: 16)` stroke (matching the `VisualEffectBackground` corner radius)
3. The stroke color interpolates between `Color.gray.opacity(0.3)` and `Color.white.opacity(0.6)` based on `edgeGlow`
4. On `.onAppear`, trigger `edgeGlow = true` with a `.easeInOut` repeating animation
5. Use `.allowsHitTesting(false)` on the overlay so it doesn't block interaction

### Code Sketch

```swift
// New state
@State private var edgeGlow: Bool = false

// Added to the HStack modifier chain (before .contextMenu)
.overlay {
    RoundedRectangle(cornerRadius: 16)
        .stroke(
            edgeGlow ? Color.white.opacity(0.6) : Color.gray.opacity(0.3),
            lineWidth: 1.5
        )
        .allowsHitTesting(false)
}
.onAppear {
    withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
        edgeGlow = true
    }
}
```

### Why this works
- The `RoundedRectangle(cornerRadius: 16)` matches the `VisualEffectBackground`'s corner radius exactly
- SwiftUI animates `Color` interpolation natively — it smoothly transitions between gray and white
- `.repeatForever(autoreverses: true)` creates a continuous pulse
- The overlay sits on top of the `VisualEffectBackground` but `.allowsHitTesting(false)` ensures clicks pass through
- The stroke is thin (1.5pt) so it's subtle but visible

### Future extensions
- Could react to mouse proximity (brighter near cursor)
- Could use a gradient stroke that rotates around the border (conic gradient)
- Could change color based on system state (e.g., red pulse when battery is low)
- Could use `ShapeStyle` with `AngularGradient` for a traveling light effect along the edge

## Files to modify
- **`DeskMat/DeskMat/ContentView.swift`** — add the animated stroke overlay

## Verification
- Build the project
- Confirm the dock edge pulses smoothly between gray and white
- Confirm all buttons, widgets, and context menus still work (hit testing not blocked)
- Confirm the stroke corners align with the background corners (both 16pt)
