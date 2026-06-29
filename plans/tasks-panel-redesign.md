# DeskMat — Tasks Panel Redesign

> **Status: in development — debug only.**
> The Tasks widget Settings toggle is gated behind `#if DEBUG` until this
> redesign is complete. See also: `plans/tasks-widget.md`.

Redesign the Tasks detail panel to match the mockup: a dark header bar with a
stitched dashed border, a clean white task list area, and a footer input row
separated by a dotted divider.

---

## Component breakdown

```
┌─────────────────────────────────┐  ← rounded corners (12pt)
│  ● [dark header bar]            │  ← Phase 1: TasksPanelHeader
│ - - - - - - - - - - - - - - -  │  ← dashed border (Canvas)
│                                 │
│   [task list — white]           │  ← Phase 2: white content area
│                                 │
│ · · · · · · · · · · · · · · ·  │  ← Phase 3: dotted divider
│   [+ add task footer]           │  ← Phase 3: TasksPanelFooter
└─────────────────────────────────┘  ← shadow beneath
```

---

## Phase 1 — Dark header with dashed border

**Goal:** Replace the current thin title bar in `WidgetPanelChrome` with a
dedicated dark header for the Tasks panel.

### New `TasksPanelHeader` view (`Widgets/Tasks/TasksPanelHeader.swift`)

- Dark near-black background: `Color(white: 0.12)`
- Fixed height: `~52pt`
- Red close button top-left (reuse existing `WidgetPanelChrome` close button style)
- Bottom edge: dashed white line drawn with `Canvas`
  - Dash pattern: 6pt on, 4pt off
  - Color: `Color.white.opacity(0.18)`
  - Positioned flush to the bottom of the header

```swift
struct TasksPanelHeader: View {
    let onClose: () -> Void
    @State private var isHoveringClose = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color(white: 0.12)

            // Close button
            Button(action: onClose) { ... }
                .padding(.top, 14).padding(.leading, 14)

            // Dashed bottom border
            Canvas { context, size in
                var path = Path()
                path.move(to: CGPoint(x: 0, y: size.height - 0.5))
                path.addLine(to: CGPoint(x: size.width, y: size.height - 0.5))
                context.stroke(path, with: .color(.white.opacity(0.18)),
                               style: StrokeStyle(lineWidth: 1,
                                                  dash: [6, 4]))
            }
        }
        .frame(height: 52)
    }
}
```

---

## Phase 2 — White content area

**Goal:** Replace the yellow notepad background in the Tasks panel with plain
white. Update text colors for white background.

### 2a. `Widgets/Tasks/TasksWidget.swift`

Remove `panelBackground` and `darkPanelTitle` — the new chrome handles its own
background. Pass `showPanelTitle: false` (already set).

Use plain `Color.white` as the panel background instead of the yellow + ruled
lines:

```swift
ExpandableWidget(title: Strings.Widgets.tasks, showPanelTitle: false) {
    // dock face — unchanged
} panelContent: {
    TasksDetailView(store: store)
}
```

### 2b. `Widgets/Tasks/TasksDetailView.swift`

Task rows and text are already using Marker Felt Thin at black opacity — these
work on white. Verify `TaskRow` check/circle icon colors look correct on white.

---

## Phase 3 — Dotted footer divider + footer row

**Goal:** Visually separate the task list from the add-task row using a dotted
line, matching the mockup's footer treatment.

### New `DottedDivider` view (inline or in `Widgets/Shared/`)

Lighter than the header dashes — gray on white:

```swift
struct DottedDivider: View {
    var body: some View {
        Canvas { context, size in
            var path = Path()
            path.move(to: CGPoint(x: 0, y: 0.5))
            path.addLine(to: CGPoint(x: size.width, y: 0.5))
            context.stroke(path, with: .color(.black.opacity(0.12)),
                           style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
        }
        .frame(height: 1)
    }
}
```

### 3a. New `TasksPanelChrome` (`Widgets/Tasks/TasksPanelChrome.swift`)

Composes all three zones into the full panel shell:

```swift
struct TasksPanelChrome<ListContent: View, FooterContent: View>: View {
    let onClose: () -> Void
    @ViewBuilder let listContent: () -> ListContent
    @ViewBuilder let footerContent: () -> FooterContent

    var body: some View {
        VStack(spacing: 0) {
            TasksPanelHeader(onClose: onClose)
            listContent()
                .background(Color.white)
            DottedDivider()
            footerContent()
                .background(Color.white)
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
    }
}
```

### 3b. `Widgets/Tasks/TasksDetailView.swift`

Split the current monolithic `body` into:
- `taskListSection` — the `List` of task rows (goes into `listContent`)
- `addTaskFooter` — the `+ Add Task` button and new-task fields (goes into
  `footerContent`)

Update `ExpandableWidget.open` call in `TasksWidget` to use `TasksPanelChrome`
instead of the generic `WidgetPanelChrome`.

---

## Phase 4 — Wire TasksWidget to TasksPanelChrome

**Goal:** `ExpandableWidget` currently wraps everything in `WidgetPanelChrome`.
For Tasks, we want full control of the chrome. Two options:

**Option A (simpler):** Pass `TasksPanelChrome` as the panel background slot —
not a good fit since the chrome controls layout, not just background.

**Option B (recommended):** Add an escape hatch to `ExpandableWidget` that
accepts a fully custom chrome builder instead of `WidgetPanelChrome`:

```swift
// New overload on ExpandableWidget
func openWithCustomChrome<Chrome: View>(
    @ViewBuilder chrome: @escaping (_ onClose: @escaping () -> Void) -> Chrome
)
```

`TasksWidget` calls this variant, passing a `TasksPanelChrome` that receives
the `onClose` callback.

---

## File change summary

| Phase | Files created / modified |
|---|---|
| 1 (dark header) | `Widgets/Tasks/TasksPanelHeader.swift` *(new)* |
| 2 (white content) | `Widgets/Tasks/TasksWidget.swift`, `TasksDetailView.swift` |
| 3 (footer + divider) | `Widgets/Tasks/TasksPanelChrome.swift` *(new)*, `TasksDetailView.swift` |
| 4 (wire up) | `Widgets/Shared/ExpandableWidget.swift`, `Widgets/Tasks/TasksWidget.swift` |

---

## Testing checklist

- [ ] Header dark background covers full width, rounded top only
- [ ] Dashed border visible at header bottom edge
- [ ] Close button red, darkens on hover, xmark on hover
- [ ] Task list white, no yellow tint
- [ ] Marker Felt text readable on white
- [ ] Dotted divider visible between list and footer
- [ ] Add task footer sits below divider, same white background
- [ ] Rounded corners clip all four corners correctly
- [ ] Shadow renders beneath the panel
- [ ] Panel still draggable (isMovableByWindowBackground on NSPanel)
- [ ] Escape key still dismisses
