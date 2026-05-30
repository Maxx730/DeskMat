# Plan: Vertical Folder Expansion

## What it looks like

Tapping a folder in the dock opens a **vertical single-column strip of app icons** that rises directly above the folder's dock slot. The strip has a dark rounded-rectangle background (same aesthetic as the dock itself) and floats above the dock. Tapping an app icon launches/focuses it and dismisses the strip. Tapping anywhere else dismisses it.

Current behavior (replaced): SwiftUI `.popover()` opens a horizontal grid popover.

---

## Architecture

The expansion strip is a **separate `NSPanel`** — the same pattern DeskMat already uses for the dock itself:

- `NSPanel` with `.nonActivatingPanel` style mask
- `NSWindow.Level.floating` so it sits above the dock panel  
- Borderless, `backgroundColor = .clear`, `isOpaque = false`
- Hosts a SwiftUI `FolderExpansionView`

**Positioning rule:**  
- Strip's horizontal center = folder icon's horizontal screen center  
- Strip's bottom edge = top edge of the dock NSPanel  
- Strip's width = single icon cell width + padding (≈ 80pt)  
- Strip's height = number of apps × (cellSize + spacing) + padding

---

## Phase 1 — FolderExpansionPanel + FolderExpansionView (static)

Create two new files:

### `FolderExpansionPanel.swift`

An `NSPanel` subclass that:
- Holds a reference to the `AppFolder` it is showing
- Exposes `show(folder:centeredAt:dockTopY:)` and `dismiss()` methods
- Hosts `FolderExpansionView` via `NSHostingView`

```swift
class FolderExpansionPanel: NSPanel {
    static let shared = FolderExpansionPanel()
    
    private var hostingView: NSHostingView<FolderExpansionView>?

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
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    func show(folder: AppFolder, centeredAt screenX: CGFloat, dockTopY: CGFloat) { ... }
    func dismiss() { ... }
}
```

### `FolderExpansionView.swift`

```swift
struct FolderExpansionView: View {
    let folder: AppFolder
    let onLaunch: () -> Void   // called after launching, dismisses the panel

    var body: some View {
        VStack(spacing: 8) {
            ForEach(folder.shortcuts) { shortcut in
                FolderExpansionCell(shortcut: shortcut, onLaunch: onLaunch)
            }
        }
        .padding(8)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .shadow(radius: 12, y: 6)
        }
    }
}
```

`FolderExpansionCell`: 64×64 icon + optional label below, `FirstMouseClickable` overlay for instant first-click response. Same icon loading pattern as `FolderAppCell`.

---

## Phase 2 — Position tracking

`FolderButton` needs to report its screen frame when tapped so the panel can be positioned correctly.

**Approach:** Use a `GeometryReader` + `PreferenceKey` in `FolderButton` to bubble its frame up to `ContentView`, which converts it to screen coordinates using the window's frame.

```swift
struct FolderFrameKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}
```

`ContentView` listens with `.onPreferenceChange(FolderFrameKey.self)` and stores a `[UUID: CGRect]` of folder screen frames.

When a folder is tapped, `ContentView` looks up the folder's screen frame and calls:
```swift
FolderExpansionPanel.shared.show(
    folder: folder,
    centeredAt: screenFrame.midX,
    dockTopY: window.frame.maxY
)
```

---

## Phase 3 — Show/Hide animation

The panel appears with a vertical slide-up + fade-in, dismisses with the reverse.

**Show:**
1. Position the panel `12pt` below its final Y — set frame, then `makeKeyAndOrderFront`
2. Animate `alphaValue` from 0 → 1 and frame Y up by 12pt using `NSAnimationContext`

**Dismiss:**
1. Animate `alphaValue` from 1 → 0 and frame Y down by 12pt
2. In the completion block call `orderOut(nil)`

Duration: 0.18s ease-out for show, 0.15s ease-in for dismiss.

The SwiftUI content inside can additionally use `.transition(.move(edge: .bottom).combined(with: .opacity))` for a staggered icon entrance effect (Phase 3b, optional).

---

## Phase 4 — Dismiss behavior

Three dismiss triggers:

1. **Click outside:** Install a global `NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown)` while the panel is visible. If the click is not inside `FolderExpansionPanel.shared.frame`, call `dismiss()`. Remove the monitor on dismiss.

2. **App launched:** `onLaunch` callback (passed into `FolderExpansionView`) calls `FolderExpansionPanel.shared.dismiss()`.

3. **Escape key:** Listen for `NSEvent.addLocalMonitorForEvents(matching: .keyDown)` on the panel; if `event.keyCode == 53` (Esc), dismiss.

---

## Phase 5 — Wire up and remove old popover

**`FolderButton.swift`:**
- Remove `@State private var showingPopover` and the `.popover(isPresented:)` modifier
- Change `.onTapGesture` to post a new notification `.openFolder` with the `AppFolder` as the object

**`ContentView.swift`:**
- Add `.onReceive` for `.openFolder` notification
- Compute the folder's screen center from stored preference frames
- Call `FolderExpansionPanel.shared.show(...)`

**`FolderButton.swift` — `FolderPopover` private struct:**  
Delete entirely (replaced by `FolderExpansionView`).

**`FolderAppCell` in `FolderButton.swift`:**  
Delete entirely (replaced by `FolderExpansionCell` in `FolderExpansionView.swift`).

---

## Files to create
- `DeskMat/FolderExpansionPanel.swift`
- `DeskMat/FolderExpansionView.swift`

## Files to change
- `DeskMat/FolderButton.swift` — remove popover, post `.openFolder` notification
- `DeskMat/ContentView.swift` — add preference change handler, call expansion panel
- `DeskMat/NotificationNames.swift` — add `.openFolder`

## Files unchanged
- `AppFolder`, `DockItem`, `AppShortcutStore` — no data model changes needed
- `FolderSheet` — the edit/create sheet is separate and unaffected
