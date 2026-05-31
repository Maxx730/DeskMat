# Clipboard History Widget — Implementation Plan

A dock widget that shows a compact clipboard icon inline, and on tap expands into a popover listing recent clipboard entries. This is visually distinct from existing widgets because it is interactive — it needs a popover list view and a backing data model — rather than a passive display.

Clipboard reading from `NSPasteboard` is **out of scope** for this plan. All phases use mock data so the visual component can be built and reviewed independently.

---

## Architecture overview

| Layer | What |
|---|---|
| `ClipboardEntry` | Value type representing one history entry (text preview, date, kind) |
| `ClipboardStore` | `@Observable` class holding `[ClipboardEntry]`; seeded with mock data for now |
| `ClipboardWidget` | Inline dock view — clipboard icon + count badge, wraps `DockWidget` |
| `ClipboardHistoryPopover` | Popover content — scrollable list of entries, clear button |

`ClipboardStore` will be injected into the SwiftUI environment the same way `WindowStateService` is, so any view can read from it.

---

## Phase 1 — Data model

**New file:** `DeskMat/ClipboardStore.swift`

### `ClipboardEntry`

```swift
struct ClipboardEntry: Identifiable {
    let id: UUID
    let preview: String   // truncated text preview shown in the list
    let date: Date
    let kind: Kind

    enum Kind {
        case text
        case image
        case other
    }
}
```

### `ClipboardStore`

```swift
@Observable
final class ClipboardStore {
    var entries: [ClipboardEntry] = []

    func clear() { entries = [] }
}
```

Seed `entries` with 5–8 hardcoded mock entries in an `#if DEBUG` block (or always for now) so the UI has something to show.

---

## Phase 2 — Inline dock widget

**New file:** `DeskMat/ClipboardWidget.swift`

Follows the same pattern as `ClockWidget`:

```swift
struct ClipboardWidget: View {
    static let cellCount = 1
    @AppStorage("showLabels") private var showLabels = true
    @Environment(ClipboardStore.self) private var store

    @State private var showingHistory = false

    var body: some View {
        VStack(spacing: 10) {
            DockWidget {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 24))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .onTapGesture { showingHistory.toggle() }
            .popover(isPresented: $showingHistory, arrowEdge: .bottom) {
                ClipboardHistoryPopover()
                    .environment(store)
            }

            if showLabels {
                Text("Clipboard")
                    .font(.caption2)
                    .lineLimit(1)
                    .frame(width: DockWidget<EmptyView>.width(for: Self.cellCount))
                    .truncationMode(.tail)
            }
        }
    }
}
```

---

## Phase 3 — History popover

**Add to:** `DeskMat/ClipboardWidget.swift` (private struct below `ClipboardWidget`)

The popover opens attached to the dock widget and lists entries newest-first.

```swift
private struct ClipboardHistoryPopover: View {
    @Environment(ClipboardStore.self) private var store

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Clipboard History")
                    .font(.headline)
                Spacer()
                Button("Clear") { store.clear() }
                    .font(.caption)
                    .foregroundStyle(.red)
                    .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            if store.entries.isEmpty {
                Text("Nothing copied yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(24)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(store.entries) { entry in
                            ClipboardEntryRow(entry: entry)
                            Divider().padding(.leading, 12)
                        }
                    }
                }
                .frame(maxHeight: 320)
            }
        }
        .frame(width: 280)
        .presentationCompactAdaptation(.none)
    }
}

private struct ClipboardEntryRow: View {
    let entry: ClipboardEntry

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: entry.kind == .image ? "photo" : "doc.text")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.preview)
                    .font(.caption)
                    .lineLimit(2)
                    .truncationMode(.tail)
                Text(entry.date.formatted(.relative(presentation: .named)))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}
```

---

## Phase 4 — Wiring

**Files:** `AppDelegate+Panel.swift`, `ContentView.swift`, `SettingsView.swift`

### 4a — Instantiate and inject `ClipboardStore`

In `AppDelegate`, add `var clipboardStore = ClipboardStore()` alongside the other services, then pass it into the SwiftUI environment in `setupPanel()`:

```swift
let content = ContentView()
    .environment(entitlements)
    .environment(systemMonitor)
    .environment(windowState)
    .environment(clipboardStore)   // add this
```

### 4b — Add to `ContentView`

Add `@AppStorage("showClipboardWidget") private var showClipboardWidget = false` and render the widget alongside the others (Pro-gated):

```swift
if entitlements.isPro && showClipboardWidget {
    ClipboardWidget()
}
```

### 4c — Add toggle to `WidgetsSettingsTab`

Add `@AppStorage("showClipboardWidget") private var showClipboardWidget = false` and a toggle following the same `proLabel` pattern as the other widgets.

### 4d — Add to `resetToDefaults`

```swift
ud.set(false, forKey: "showClipboardWidget")
```

---

## Acceptance criteria

- The clipboard icon appears inline in the dock when the widget is enabled.
- Tapping the widget opens the popover listing mock entries with previews and relative timestamps.
- "Clear" empties the list and the badge disappears.
- Disabling the widget from Settings hides it.
- No `NSPasteboard` code exists yet — all data is mock.
- All existing widgets continue to function correctly.
