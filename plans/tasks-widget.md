# DeskMat — Tasks Widget

> **Status: in development — debug only.**
> The Settings toggle is currently gated behind `#if DEBUG` and lives in the
> Debug section of the Widgets tab. It will be moved to the main widget list
> once the widget is production-ready.

A persistent checklist widget that lives in the dock. The widget is **2 cells
wide** — double the standard single-icon slot — to give enough horizontal space
for a readable task list. Tasks (title + completion state) survive app restarts
via a `TasksStore` backed by `UserDefaults` / `JSONEncoder`.

---

## Architecture overview

All existing widgets follow the same four-file pattern:

| File | Role |
|---|---|
| `Widgets/Tasks/TasksWidget.swift` | Top-level SwiftUI view, drives the list |
| `Widgets/Tasks/TasksStore.swift` | Persistence layer — encodes `[Task]` to `UserDefaults` |
| `ContentView.swift` | Renders widget when `showTasksWidget == true` |
| `SettingsView.swift` | Toggle + sub-options |

The widget is fixed at **`cellCount = 2`** (two dock cells wide). This is a
deliberate design constraint — not user-configurable — since it balances
readability with dock real estate. Width resolves to
`DockWidget.width(for: 2)` at runtime.

---

## Phase 1 — Scaffold (placeholder)

**Goal:** Get the widget appearing in the dock behind a settings toggle with
zero functional code.

### 1a. `Widgets/Tasks/TasksWidget.swift`

```swift
import SwiftUI

struct TasksWidget: View {
    static let cellCount = 2

    var body: some View {
        VStack(spacing: 6) {
            DockWidget {
                Text("Tasks")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(
                        width:  DockWidget<EmptyView>.width(for: Self.cellCount),
                        height: DockWidget<EmptyView>.height
                    )
            }
        }
    }
}
```

### 1b. `ContentView.swift`

Add `@AppStorage`:
```swift
@AppStorage("showTasksWidget") private var showTasksWidget = false
```

Add to the widget `HStack` (after `MediaControlWidget`):
```swift
if entitlements.isPro && showTasksWidget {
    TasksWidget()
}
```

### 1c. `SettingsView.swift`

Add `@AppStorage` in `WidgetSettingsView`:
```swift
@AppStorage("showTasksWidget") private var showTasksWidget = false
```

Add toggle in the widget list:
```swift
Toggle(isOn: $showTasksWidget) {
    proLabel("Tasks Widget", isPro: license.isPro)
}
.disabled(!license.isPro)
```

Add to `resetDefaults()`:
```swift
ud.set(false, forKey: "showTasksWidget")
```

### 1d. `Core/Strings.swift`

Add to `Strings.Widgets`:
```swift
static let tasks = "Tasks"
```

---

## Phase 2 — Live checklist

**Goal:** Replace the placeholder with a functional task list.

- Define `Task` model: `struct Task: Identifiable, Codable { var id: UUID; var title: String; var isDone: Bool }`
- Introduce `TasksStore.swift` — reads/writes `[Task]` to `UserDefaults` via `JSONEncoder`
- Render tasks as a scrollable `List` of toggle rows inside `DockWidget`
- Tapping a row flips `isDone`; completed tasks show a strikethrough title
- "+" button at the bottom adds a new empty task (inline text field on creation)
- Swipe-to-delete or right-click context menu removes a task

---

## Phase 3 — Inline editing & reorder

**Goal:** Let the user edit task titles in place and reorder the list.

- Tap an existing task title to enter edit mode (inline `TextField`)
- Long-press drag handle (or `.onMove`) for drag-to-reorder
- Changes write through to `TasksStore` on every edit (no explicit save step)
- "Clear completed" action in a context menu on the widget background

---

## Phase 4 — Polish & settings

**Goal:** Make the widget feel like a first-class dock citizen.

- Settings sub-section: show/hide completed tasks, sort order (manual / by status)
- Optional colored accent per task (uses existing `ColorUtils`)
- Completed task count badge on the widget label (e.g. "3 / 5")
- Animate row insertion / deletion with `.transition(.slide)`
- Export task list as plain `.txt` via `NSSavePanel`

---

## File change summary

| Phase | Files touched |
|---|---|
| 1 (scaffold) | `Widgets/Tasks/TasksWidget.swift` *(new)*, `ContentView.swift`, `SettingsView.swift`, `Core/Strings.swift` |
| 2 (live checklist) | `Widgets/Tasks/TasksWidget.swift`, `Widgets/Tasks/TasksStore.swift` *(new)* |
| 3 (editing & reorder) | `Widgets/Tasks/TasksWidget.swift`, `Widgets/Tasks/TasksStore.swift` |
| 4 (polish) | `Widgets/Tasks/TasksWidget.swift`, `Settings/SettingsView.swift` |

---

## Testing checklist

- [ ] Widget appears in Settings toggle list (Pro-gated)
- [ ] Widget renders placeholder in dock at correct size
- [ ] Toggling off removes widget from dock without crash
- [ ] (Phase 2) Tasks persist across app restarts
- [ ] (Phase 2) Checking a task persists its `isDone` state
- [ ] (Phase 3) Reordering survives a restart in the new order
- [ ] (Phase 4) Completed count badge updates as tasks are checked off
