# DeskMat — Expandable Widget

A reusable foundation that makes any dock widget clickable: tapping it opens a
floating, **movable sub-window** that the user can drag anywhere on screen and
close independently. `TasksWidget` and `NotesWidget` will both be built on top
of this, and any future widget can adopt it for free.

---

## Architecture overview

This is distinct from `FolderExpansionPanel`, which is a fixed panel anchored
above the dock. The widget detail window is a first-class floating window:
movable by the user, stays open until explicitly closed, and has its own close
button. It does not dismiss on outside-click.

Two shared files do all the work:

| Piece | Role |
|---|---|
| `Widgets/Shared/WidgetDetailPanel.swift` | Per-widget `NSPanel` subclass — movable, borderless, hosts any SwiftUI view |
| `Widgets/Shared/ExpandableWidget.swift` | SwiftUI wrapper — owns a `WidgetDetailPanel`, opens it on tap |

`FolderExpansionPanel` is **not changed** — it is a different UX pattern
(anchored popover vs detached window).

```
Tap on TasksWidget
    └─ ExpandableWidget.onTap()
           ├─ reads own frame via GeometryReader
           ├─ finds DeskMatPanel to compute initial spawn position
           └─ widgetDetailPanel.open(content: TasksDetailView())
                  └─ NSPanel: movable, stays open, user closes via × button
```

**Per-widget, not singleton.** Each `ExpandableWidget` instance owns its own
`WidgetDetailPanel`. This means Tasks and Notes can have their windows open at
the same time, each independently positioned by the user.

---

## Phase 1 — WidgetDetailPanel

**Goal:** A movable floating `NSPanel` that can host any SwiftUI view, with a
close button in the content. No visible product change — nothing calls it yet.

### Design decisions

| Property | Value | Reason |
|---|---|---|
| `styleMask` | `.borderless`, `.nonactivatingPanel` | Custom SwiftUI chrome; no system title bar |
| `isMovable` | `true` | User can drag it anywhere |
| `isMovableByWindowBackground` | `true` | Drag anywhere on the window body, not just a title bar |
| `hasShadow` | `true` | Floats visually above the desktop |
| `level` | `.floating` | Stays above regular app windows |
| `collectionBehavior` | `.canJoinAllSpaces`, `.fullScreenAuxiliary` | Follows the user across Spaces |
| Outside-click monitor | **none** | Window stays open; user closes it explicitly |
| `canBecomeKey` | `true` | Needed so text fields inside (Notes, Tasks) can receive keyboard input |

### 1a. `Widgets/Shared/WidgetDetailPanel.swift` *(new)*

```swift
import AppKit
import SwiftUI

final class WidgetDetailPanel: NSPanel {

    private var hostingView: NSHostingView<AnyView>?
    private(set) var isShowing = false

    private var escapeKeyMonitor: Any?

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .floating
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        isMovable = true
        isMovableByWindowBackground = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    override var canBecomeKey: Bool { true }

    // MARK: - Show / Hide

    func open<Content: View>(
        @ViewBuilder content: () -> Content,
        spawnAt origin: CGPoint
    ) {
        isShowing = true
        let wrapped = AnyView(content())

        if let hv = hostingView {
            hv.rootView = wrapped
        } else {
            let hv = NSHostingView(rootView: wrapped)
            hv.autoresizingMask = [.width, .height]
            contentView = hv
            hostingView = hv
        }

        sizeToFitContent()
        setFrameOrigin(origin)

        alphaValue = 0
        orderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().alphaValue = 1
        }

        installEscapeMonitor()
    }

    func close() {
        guard isShowing else { return }
        isShowing = false
        removeEscapeMonitor()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            self.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            self?.orderOut(nil)
            self?.alphaValue = 1
        }
    }

    // MARK: - Escape key

    private func installEscapeMonitor() {
        removeEscapeMonitor()
        escapeKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { self?.close(); return nil }
            return event
        }
    }

    private func removeEscapeMonitor() {
        if let m = escapeKeyMonitor { NSEvent.removeMonitor(m); escapeKeyMonitor = nil }
    }

    // MARK: - Layout

    private func sizeToFitContent() {
        guard let hv = hostingView else { return }
        hv.layout()
        var size = hv.fittingSize
        if size.width  <= 0 { size.width  = 240 }
        if size.height <= 0 { size.height = 300 }
        setContentSize(size)
    }
}
```

### 1b. Close button chrome

Each panel's SwiftUI content is responsible for its own close button. A shared
modifier keeps it consistent:

```swift
// Widgets/Shared/WidgetDetailPanel.swift (bottom of file)

struct WidgetPanelChrome<Content: View>: View {
    let title: String
    let onClose: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            // Drag handle / title bar
            HStack {
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            content()
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 8, y: 4)
    }
}
```

---

## Phase 2 — ExpandableWidget SwiftUI wrapper

**Goal:** A generic SwiftUI view that any widget can use to open its detail
window on tap — self-contained, no `ContentView` changes needed.

### 2a. `Widgets/Shared/ExpandableWidget.swift` *(new)*

```swift
import SwiftUI
import AppKit

struct ExpandableWidget<DockContent: View, PanelContent: View>: View {
    let title: String
    @ViewBuilder let dockContent: () -> DockContent
    @ViewBuilder let panelContent: () -> PanelContent

    @State private var widgetFrame: CGRect = .zero
    @State private var isOpen = false
    @State private var detailPanel = WidgetDetailPanel()

    var body: some View {
        dockContent()
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear { widgetFrame = geo.frame(in: .global) }
                        .onChange(of: geo.frame(in: .global)) { _, f in widgetFrame = f }
                }
            )
            .onTapGesture { togglePanel() }
    }

    private func togglePanel() {
        if isOpen {
            detailPanel.close()
            isOpen = false
            return
        }
        isOpen = true
        let spawnOrigin = spawnPoint()
        detailPanel.open(
            content: {
                WidgetPanelChrome(title: title, onClose: {
                    detailPanel.close()
                    isOpen = false
                }) {
                    panelContent()
                }
            },
            spawnAt: spawnOrigin
        )
    }

    // Spawn just above the dock, horizontally centred on this widget.
    private func spawnPoint() -> CGPoint {
        guard let dockPanel = NSApp.windows.first(where: { $0 is DeskMatPanel }) else {
            return NSEvent.mouseLocation
        }
        let screenCenterX = dockPanel.frame.minX + widgetFrame.midX
        let dockTopY      = dockPanel.frame.maxY
        // Offset will be adjusted after sizeToFitContent(); rough initial position.
        return CGPoint(x: screenCenterX - 120, y: dockTopY + 8)
    }
}
```

> `detailPanel` is a `@State` property — SwiftUI owns it for the lifetime of
> the widget view. Because each `ExpandableWidget` instance has its own panel
> instance, Tasks and Notes windows are fully independent.

---

## Phase 3 — Refactor TasksWidget to use ExpandableWidget

**Goal:** Replace the placeholder `TasksWidget` with a real checklist panel.

### Touch points

| File | Change |
|---|---|
| `Widgets/Tasks/TasksWidget.swift` | Wraps `ExpandableWidget`; compact dock icon + `TasksDetailView` as panel |
| `Widgets/Tasks/TasksDetailView.swift` *(new)* | Full checklist UI: toggle rows, add button, swipe-to-delete |
| `Widgets/Tasks/TasksStore.swift` *(new)* | `Task` model + `UserDefaults`/`JSONEncoder` persistence |

### Compact dock face

```swift
DockWidget(cells: 2) {
    VStack(spacing: 2) {
        Image(systemName: "checklist")
            .font(.system(size: 20))
        Text(Strings.Widgets.tasks)
            .font(.caption2)
    }
    .foregroundStyle(.white.opacity(0.85))
}
```

### Panel content (`TasksDetailView`)

Rendered inside `WidgetPanelChrome` at ~280 pt wide:
- `List` of `TaskRow` — checkbox + title, strikethrough when done
- "+" button in the panel header adds an empty task with inline `TextField` focused
- Swipe-to-delete (`.onDelete`) removes a task
- `TasksStore` (`@Observable`) persists on every mutation

---

## Phase 4 — Implement NotesWidget using ExpandableWidget

**Goal:** Notes widget uses `ExpandableWidget` from day one, sharing the same
panel infrastructure as Tasks.

### Touch points

| File | Change |
|---|---|
| `Widgets/Notes/NotesWidget.swift` *(new)* | `ExpandableWidget` wrapper, 2 cells wide |
| `Widgets/Notes/NotesDetailView.swift` *(new)* | `TextEditor` panel, auto-saves on every keystroke |
| `Widgets/Notes/NotesStore.swift` *(new)* | Persists note text via `@AppStorage` |
| `ContentView.swift` | Add `showNotesWidget` guard + `NotesWidget()` |
| `SettingsView.swift` | Add Notes toggle (Pro-gated) |
| `Core/Strings.swift` | Add `Strings.Widgets.notes` |

### Compact dock face

```swift
DockWidget(cells: 2) {
    VStack(spacing: 2) {
        Image(systemName: "note.text")
            .font(.system(size: 20))
        Text(Strings.Widgets.notes)
            .font(.caption2)
    }
    .foregroundStyle(.white.opacity(0.85))
}
```

### Panel content (`NotesDetailView`)

Rendered inside `WidgetPanelChrome` at ~280 pt wide:
- `TextEditor` filling available height (~300 pt default)
- Character count footer
- Auto-saves on every keystroke via `NotesStore`

---

## File change summary

| Phase | Files touched |
|---|---|
| 1 (panel infra) | `Widgets/Shared/WidgetDetailPanel.swift` *(new)* |
| 2 (SwiftUI wrapper) | `Widgets/Shared/ExpandableWidget.swift` *(new)* |
| 3 (Tasks) | `Widgets/Tasks/TasksWidget.swift`, `Widgets/Tasks/TasksDetailView.swift` *(new)*, `Widgets/Tasks/TasksStore.swift` *(new)* |
| 4 (Notes) | `Widgets/Notes/NotesWidget.swift` *(new)*, `Widgets/Notes/NotesDetailView.swift` *(new)*, `Widgets/Notes/NotesStore.swift` *(new)*, `ContentView.swift`, `SettingsView.swift`, `Core/Strings.swift` |

---

## Testing checklist

- [ ] Tapping a widget opens a floating window near the dock
- [ ] The window can be freely dragged to any position on screen
- [ ] Clicking the × button closes the window
- [ ] Pressing Escape closes the window
- [ ] Tapping the same widget again while the window is open closes it
- [ ] Tasks and Notes windows can be open simultaneously, independently positioned
- [ ] Window stays visible when clicking elsewhere on the desktop
- [ ] Window appears on all Spaces / over fullscreen apps
- [ ] (Phase 3) Tasks list renders at correct size in the panel
- [ ] (Phase 3) Tasks persist across app restarts
- [ ] (Phase 4) Notes text persists across app restarts
