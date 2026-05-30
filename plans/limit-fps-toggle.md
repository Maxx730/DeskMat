# Limit FPS Toggle — Implementation Plan

Add a "Limit FPS" toggle to the settings panel that only appears when the Reactive
background is selected. When enabled (default on), the view runs at the current
15/30fps idle/hover limits. When disabled, it runs uncapped at the display's native
refresh rate.

---

## What changes

### Phase 1 — Persist the setting

**File:** `DeskMat/SettingsView.swift`

Add an `@AppStorage` property alongside the other reactive settings:

```swift
@AppStorage("limitReactiveFPS") private var limitReactiveFPS: Bool = true
```

**File:** `DeskMat/SettingsView.swift` — `resetDefaults()`

Register the default in the reset block:

```swift
ud.set(true, forKey: "limitReactiveFPS")
```

---

### Phase 2 — Add the toggle to the UI

**File:** `DeskMat/SettingsView.swift`

Inside the existing `if dockBackground == .reactive { }` block, after the style
picker, add:

```swift
Toggle(isOn: $limitReactiveFPS) {
    VStack(alignment: .leading, spacing: 2) {
        Text("Limit FPS")
        Text("Higher frame rates increase power usage.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
```

The toggle is only visible when `dockBackground == .reactive`, so it never
appears for other background modes.

---

### Phase 3 — Wire the setting into ReactiveBackgroundRepresentable

**File:** `DeskMat/ReactiveBackgroundView.swift`

Add `limitFPS: Bool` to the representable struct and pass it through
`updateNSView`:

```swift
struct ReactiveBackgroundRepresentable: NSViewRepresentable {
    let style:        ReactiveStyle
    let cornerRadius: CGFloat
    let limitFPS:     Bool

    func makeNSView(context: Context) -> ReactiveBackgroundView {
        ReactiveBackgroundView()
    }

    func updateNSView(_ nsView: ReactiveBackgroundView, context: Context) {
        nsView.reactiveStyle = style
        nsView.cornerRadius  = cornerRadius
        nsView.limitFPS      = limitFPS
    }
}
```

**File:** `DeskMat/ContentView.swift`

Pass the stored value at the call site:

```swift
ReactiveBackgroundRepresentable(
    style:        reactiveStyle,
    cornerRadius: dockCornerRadius,
    limitFPS:     limitReactiveFPS
)
```

Add `@AppStorage("limitReactiveFPS") private var limitReactiveFPS: Bool = true`
to `ContentView` alongside the other reactive storage properties.

---

### Phase 4 — Respect the flag in ReactiveBackgroundView

**File:** `DeskMat/ReactiveBackgroundView.swift`

Add the stored property:

```swift
var limitFPS: Bool = true {
    didSet { applyFrameRateLimit() }
}
```

Extract frame rate application into a single helper so hover enter/exit and the
`didSet` all call the same place:

```swift
private func applyFrameRateLimit() {
    if limitFPS {
        metalView.preferredFramesPerSecond = isHovering ? 30 : 15
    } else {
        metalView.preferredFramesPerSecond = 0  // 0 = display native (uncapped)
    }
}
```

Replace the three existing `metalView.preferredFramesPerSecond = …` lines with
calls to `applyFrameRateLimit()`:

- In `setup()`: replace `metalView.preferredFramesPerSecond = 15`
- In `mouseEntered`: replace `metalView.preferredFramesPerSecond = 30`
- In `mouseExited`: replace `metalView.preferredFramesPerSecond = 15`

---

## Acceptance criteria

- Toggle only appears when Dock Background is set to Reactive.
- Default state is **on** (limited).
- Toggling off visibly smooths animations (higher frame rate).
- Toggling back on immediately drops back to 15/30fps.
- Setting persists across app restarts.
- Reset Defaults restores the toggle to on.
