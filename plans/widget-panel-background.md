# DeskMat — Widget Panel Custom Background

Add support for a custom background on the `WidgetDetailPanel` chrome. Each
widget can supply its own background view — defaulting to `.regularMaterial` so
nothing changes unless explicitly overridden. `TasksWidget` will be the first
consumer, using a notepad paper background to match its dock face.

---

## Architecture overview

The background sits in `WidgetPanelChrome`, which is the single place that
renders the panel's visual shell. The goal is to make that background slot
generic — accepting any SwiftUI `View` — while keeping the existing
`.regularMaterial` as the default.

The change threads through three layers:

```
WidgetPanelChrome<Content, Background>
    ↑ constructed by
ExpandableWidget (new panelBackground parameter)
    ↑ called by
TasksWidget / NotesWidget / future widgets
```

---

## Phase 1 — Generify WidgetPanelChrome

**Goal:** Make `WidgetPanelChrome` accept a generic background view. No visible
change — the default is identical to the current `.regularMaterial`.

### 1a. `Widgets/Shared/WidgetDetailPanel.swift`

Add a second generic parameter `Background: View` and a `@ViewBuilder background`
closure. Replace the hardcoded `.background(.regularMaterial, ...)` with the
provided view:

```swift
struct WidgetPanelChrome<Content: View, Background: View>: View {
    let title: String
    let onClose: () -> Void
    @ViewBuilder let background: () -> Background
    @ViewBuilder let content: () -> Content

    // ... existing close button state ...

    var body: some View {
        VStack(spacing: 0) {
            // ... existing title bar ...
            content()
        }
        .background(in: RoundedRectangle(cornerRadius: 12)) {
            background()
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 8, y: 4)
    }
}
```

Provide a convenience initialiser that defaults to `.regularMaterial` so existing
call sites require zero changes:

```swift
extension WidgetPanelChrome where Background == _ShapeView<RoundedRectangle, Material> {
    init(
        title: String,
        onClose: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(title: title, onClose: onClose, background: {
            RoundedRectangle(cornerRadius: 12).fill(.regularMaterial)
        }, content: content)
    }
}
```

> **Note:** The exact default initialiser signature depends on how SwiftUI's
> `_ShapeView` resolves at compile time. If it doesn't cleanly constrain, use
> `AnyView` for the default or a `MaterialBackground` helper struct.

---

## Phase 2 — Thread through ExpandableWidget

**Goal:** Let callers of `ExpandableWidget` pass a background without touching
`WidgetDetailPanel` internals.

### 2a. `Widgets/Shared/ExpandableWidget.swift`

Add an optional `@ViewBuilder panelBackground` parameter. When provided, it is
forwarded to `WidgetPanelChrome`'s `background` argument. When omitted, the
default material initialiser is used.

```swift
struct ExpandableWidget<DockContent: View, PanelContent: View, PanelBackground: View>: View {
    let title: String
    @ViewBuilder let dockContent: () -> DockContent
    @ViewBuilder let panelContent: () -> PanelContent
    @ViewBuilder let panelBackground: () -> PanelBackground

    // ... existing state ...
}
```

Add a convenience initialiser where `PanelBackground == Never` (or a default
material wrapper) so existing callers that don't pass a background keep working
unchanged.

---

## Phase 3 — TasksWidget notepad panel background

**Goal:** `TasksWidget` uses `NotePaperBackground` as the panel background,
matching the dock face aesthetic. The panel title bar gets a light yellow tint;
the content area shows ruled lines.

### 3a. `Widgets/Shared/NotePaperBackground.swift` (already exists)

No changes needed — reuse as-is for the panel.

### 3b. `Widgets/Tasks/TasksWidget.swift`

Pass a `panelBackground` to `ExpandableWidget`:

```swift
ExpandableWidget(title: Strings.Widgets.tasks) {
    // dock face — unchanged
} panelContent: {
    TasksDetailView(store: store)
} panelBackground: {
    ZStack {
        Color(red: 1.0, green: 0.96, blue: 0.70)
        NotePaperBackground(lineSpacing: 22, marginX: 24)
    }
}
```

The `lineSpacing` is wider than the dock face (22pt vs 11pt) to suit the taller
panel content area. `marginX` is pushed out slightly to account for the panel's
wider frame.

---

## Phase 4 — Per-widget panel background settings (optional / future)

**Goal:** Let the user pick a panel background for each widget from a preset
list in Settings. Presets include:

| Key | Preview |
|---|---|
| `material` | System `.regularMaterial` (default) |
| `notePaper` | Yellow ruled paper |
| `dark` | `Color.black.opacity(0.75)` |
| `color` | User-picked solid colour via `ColorPicker` |

Implementation sketch:
- `WidgetPanelBackgroundPreset` enum stored in `@AppStorage`
- Factory function `backgroundView(for: WidgetPanelBackgroundPreset) -> AnyView`
- `ExpandableWidget` reads the preset from `@AppStorage` and resolves the view

---

## File change summary

| Phase | Files touched |
|---|---|
| 1 (generify chrome) | `Widgets/Shared/WidgetDetailPanel.swift` |
| 2 (thread through) | `Widgets/Shared/ExpandableWidget.swift` |
| 3 (Tasks notepad) | `Widgets/Tasks/TasksWidget.swift` |
| 4 (settings presets) | `Widgets/Shared/ExpandableWidget.swift`, `Settings/SettingsView.swift`, new `WidgetPanelBackgroundPreset.swift` |

---

## Testing checklist

- [ ] Default panel background unchanged for all existing widgets
- [ ] TasksWidget panel shows yellow ruled paper background
- [ ] Close button remains readable on all backgrounds
- [ ] Title bar text readable on custom backgrounds
- [ ] Panel shadow renders correctly on all backgrounds
- [ ] (Phase 4) Setting persists across app restarts
- [ ] (Phase 4) Changing preset updates open panel immediately
