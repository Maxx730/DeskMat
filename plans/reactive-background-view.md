# Reactive Background View — Implementation Plan

A new pro-only dock background that tracks the mouse position and draws
a red circle under the cursor. Default background is black.

---

## Current state

| Layer | Status |
|---|---|
| `DockBackground.reactive` enum case | Added |
| Settings picker | Shows "Reactive (Pro Only)" when not pro; disabled |
| `ContentView` switch | Falls through to `Color.clear` — placeholder |
| `ReactiveBackgroundView.swift` | Does not exist yet |

---

## Phase 1 — Scaffold the view

**Goal:** a named file that compiles and renders a solid black background.
No interaction yet.

**New file:** `DeskMat/ReactiveBackgroundView.swift`

```swift
struct ReactiveBackgroundView: View {
    var body: some View {
        Color.black
    }
}
```

**Wire it up in `ContentView.swift`:**

```swift
case .reactive:
    ReactiveBackgroundView()
```

**Acceptance criteria:**
- Selecting Reactive in Settings (as a pro user) shows a black dock background.
- No compiler warnings.

---

## Phase 2 — Mouse position tracking

**Goal:** the view knows where the mouse is while it hovers over it.

Use SwiftUI's `.onContinuousHover` (macOS 13+) to receive the cursor
position in view-local coordinates. Store it as `CGPoint?` — `nil` when
the cursor is outside the view.

```swift
@State private var mousePosition: CGPoint? = nil

Color.black
    .onContinuousHover { phase in
        switch phase {
        case .active(let location): mousePosition = location
        case .ended:                mousePosition = nil
        }
    }
```

**Acceptance criteria:**
- `mousePosition` updates as the mouse moves over the dock.
- `mousePosition` returns to `nil` when the mouse leaves.
- No visible change to the rendered background yet.

---

## Phase 3 — Draw the circle

**Goal:** render a red circle centered on `mousePosition` when it is non-nil.

Overlay a `Canvas` on top of the background so drawing stays outside the
SwiftUI layout system and doesn't affect hit-testing or sizing.

```swift
Color.black
    .overlay {
        Canvas { context, _ in
            guard let pos = mousePosition else { return }
            let radius: CGFloat = 20
            let rect = CGRect(
                x: pos.x - radius, y: pos.y - radius,
                width: radius * 2, height: radius * 2
            )
            context.fill(Path(ellipseIn: rect), with: .color(.red))
        }
    }
    .onContinuousHover { ... }
```

> `Canvas` re-renders automatically when its captured values change, so
> capturing `mousePosition` directly in the closure is enough.

**Acceptance criteria:**
- A red circle appears at the cursor position while hovering.
- The circle disappears when the cursor leaves the view.
- Circle stays within the view bounds (no overflow artefacts).

---

## Phase 4 — Animation polish

**Goal:** smooth movement and fade rather than a hard jump/snap.

Two additions:

1. **Position smoothing** — animate `mousePosition` changes with an
   interactive spring so the circle follows the cursor with slight lag.

2. **Fade in / out** — animate opacity when entering and leaving so the
   circle doesn't pop on and off.

```swift
@State private var mousePosition: CGPoint? = nil
@State private var circleOpacity: Double = 0

// In the hover handler:
case .active(let location):
    withAnimation(.interactiveSpring(response: 0.15)) {
        mousePosition = location
    }
    withAnimation(.easeIn(duration: 0.1)) { circleOpacity = 1 }
case .ended:
    withAnimation(.easeOut(duration: 0.2)) { circleOpacity = 0 }
    // Delay nil so the fade-out completes before circle disappears
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
        mousePosition = nil
    }
```

Apply `circleOpacity` to the canvas fill color:
```swift
context.fill(..., with: .color(.red.opacity(circleOpacity)))
```

**Acceptance criteria:**
- Circle smoothly follows the mouse with slight spring lag.
- Circle fades in on entry and fades out on exit.
- No visual glitches at view edges.

---

## Out of scope (future phases)

- Configurable circle color, radius, or opacity via Settings.
- Multiple trail circles / particle effects.
- Reacting to click events.
- Syncing with audio or system metrics.
