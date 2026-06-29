# DeskMat — Notes Widget

A persistent quick-note widget that lives in the dock. The widget is **2 cells
wide** — double the standard single-icon slot — to give enough horizontal space
for readable text. The user can type short notes directly into the dock widget;
notes survive app restarts via `UserDefaults` / `AppStorage`.

---

## Architecture overview

All existing widgets follow the same four-file pattern:

| File | Role |
|---|---|
| `Widgets/Notes/NotesWidget.swift` | Top-level SwiftUI view, owns `@AppStorage` |
| `Widgets/Notes/NotesStore.swift` | Persistence layer (read/write) |
| `ContentView.swift` | Renders widget when `showNotesWidget == true` |
| `SettingsView.swift` | Toggle + sub-options |

The widget is fixed at **`cellCount = 2`** (two dock cells wide). This is a
deliberate design constraint — not user-configurable — since it balances
readability with dock real estate. Width resolves to
`DockWidget.width(for: 2)` at runtime.

---

## Phase 1 — Scaffold (placeholder)

**Goal:** Get the widget appearing in the dock behind a settings toggle with
zero functional code.

### 1a. `Widgets/Notes/NotesWidget.swift`

```swift
import SwiftUI

struct NotesWidget: View {
    static let cellCount = 2

    var body: some View {
        VStack(spacing: 6) {
            DockWidget {
                Text("Notes")
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
@AppStorage("showNotesWidget") private var showNotesWidget = false
```

Add to the widget `HStack` (after `MediaControlWidget`):
```swift
if entitlements.isPro && showNotesWidget {
    NotesWidget()
}
```

### 1c. `SettingsView.swift`

Add `@AppStorage` in `WidgetSettingsView`:
```swift
@AppStorage("showNotesWidget") private var showNotesWidget = false
```

Add toggle in the widget list:
```swift
Toggle(isOn: $showNotesWidget) {
    proLabel("Notes Widget", isPro: license.isPro)
}
.disabled(!license.isPro)
```

Add to `resetDefaults()`:
```swift
ud.set(false, forKey: "showNotesWidget")
```

### 1d. `Core/Strings.swift`

Add to `Strings.Widgets`:
```swift
static let notes = "Notes"
```

---

## Phase 2 — Editable text

**Goal:** Replace the placeholder with a live `TextEditor` the user can type
into. Notes persist via `@AppStorage`.

- `@AppStorage("notesContent") var content: String = ""`
- `TextEditor(text: $content)` inside `DockWidget`
- Strip SwiftUI's default white background with `.scrollContentBackground(.hidden)`
- Limit to ~400 characters to keep the dock slot compact

---

## Phase 3 — Multi-note support

**Goal:** Let the user maintain multiple named notes and flip between them.

- Introduce `NotesStore.swift` — encodes `[Note]` (id, title, body) to
  `UserDefaults` via `JSONEncoder`
- Add a tab-strip or arrow navigation at the top of the widget to switch notes
- "+" button creates a new note; long-press or right-click deletes
- Active note index persisted in `@AppStorage("notesActiveIndex")`

---

## Phase 4 — Formatting & polish

**Goal:** Make the widget feel like a first-class dock citizen.

- Font size picker (caption / body / headline)
- Optional colored background per note (pulls from existing `ColorUtils`)
- Character / line count indicator at bottom edge
- Smooth height animation when content grows (if dock orientation allows)
- Export note as `.txt` via `NSSavePanel`

---

## File change summary

| Phase | Files touched |
|---|---|
| 1 (scaffold) | `Widgets/Notes/NotesWidget.swift` *(new)*, `ContentView.swift`, `SettingsView.swift`, `Core/Strings.swift` |
| 2 (editable) | `Widgets/Notes/NotesWidget.swift` |
| 3 (multi-note) | `Widgets/Notes/NotesWidget.swift`, `Widgets/Notes/NotesStore.swift` *(new)* |
| 4 (polish) | `Widgets/Notes/NotesWidget.swift`, `Settings/SettingsView.swift` |

---

## Testing checklist

- [ ] Widget appears in Settings toggle list (Pro-gated)
- [ ] Widget renders placeholder in dock at correct size
- [ ] Toggling off removes widget from dock without crash
- [ ] (Phase 2) Typed text survives app restart
- [ ] (Phase 3) Switching notes preserves both notes' content
- [ ] (Phase 4) Colored background matches selected color
