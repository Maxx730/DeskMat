import SwiftUI
import AppKit

struct ContentView: View {
    @State private var shortcuts: [AppShortcut] = AppShortcutStore.load()
    @AppStorage("showWeatherWidget") private var showWeatherWidget = true
    @AppStorage("showClockWidget") private var showClockWidget = true
    @AppStorage("showImageWidget") private var showImageWidget = true
    @AppStorage("showLEDBoard") private var showLEDBoard = true
    @AppStorage("dockBackground") private var dockBackground: DockBackground = .system
    @AppStorage("dockBackgroundColorHex") private var dockBackgroundColorHex: String = "#000000ff"

    // Drag-to-reorder state
    @State private var draggingID: UUID? = nil
    @State private var draggingShortcut: AppShortcut? = nil
    @State private var draggingIcon: Image? = nil
    @State private var dragPosition: CGPoint = .zero
    @State private var displayShortcuts: [AppShortcut?] = []
    @State private var targetIndex: Int = 0
    @State private var windowContentHeight: CGFloat = 0
    @State private var isShaking: Bool = false
    private static var dragMonitorToken: Any?

    var body: some View {
        ZStack {
            HStack {
                if showWeatherWidget {
                    WeatherWidget()
                }

                if draggingID != nil {
                    ForEach(displayShortcuts.indices, id: \.self) { i in
                        if let shortcut = displayShortcuts[i] {
                            AppShortcutButton(
                                shortcut: shortcut,
                                onRemove: { removeShortcut(shortcut) },
                                isReordering: true,
                                onDragStart: { icon in dragStart(shortcut: shortcut, icon: icon) }
                            )
                        } else {
                            Color.clear.frame(width: 64, height: 64)
                        }
                    }
                } else {
                    ForEach(shortcuts) { shortcut in
                        AppShortcutButton(
                            shortcut: shortcut,
                            onRemove: { removeShortcut(shortcut) },
                            isReordering: false,
                            onDragStart: { icon in dragStart(shortcut: shortcut, icon: icon) }
                        )
                    }
                }

                if showImageWidget {
                    ImageWidget()
                }

                if showLEDBoard {
                    LEDBoardWidget()
                }

                if showClockWidget {
                    ClockWidget()
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .animation(.spring(duration: 0.2), value: displayShortcuts.map { $0?.id })
            .contextMenu {
                Button(Strings.Menu.addShortcut) {
                    NotificationCenter.default.post(name: .addShortcut, object: nil)
                }
                Divider()
                Button(Strings.Menu.exportDock) {
                    NotificationCenter.default.post(name: .exportDock, object: nil)
                }
                Button(Strings.Menu.importDock) {
                    NotificationCenter.default.post(name: .importDock, object: nil)
                }
                Divider()
                Button(Strings.Menu.settings) {
                    NotificationCenter.default.post(name: .openSettings, object: nil)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .shortcutAdded)) { notification in
                if let newShortcut = notification.object as? AppShortcut {
                    shortcuts.append(newShortcut)
                    AppShortcutStore.save(shortcuts)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .shortcutEdited)) { notification in
                if let updated = notification.object as? AppShortcut {
                    updateShortcut(updated)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .dockImported)) { notification in
                if let imported = notification.object as? [AppShortcut] {
                    shortcuts = imported
                }
            }

            if draggingShortcut != nil {
                DragGhostIcon(icon: draggingIcon, isShaking: isShaking)
                    .allowsHitTesting(false)
                    .position(x: dragPosition.x, y: dragPosition.y)
            }
        }
        .background(GeometryReader { geo in
            Color.clear
                .onAppear { windowContentHeight = geo.size.height }
                .onChange(of: geo.size.height) { _, h in windowContentHeight = h }
        })
        .background {
            switch dockBackground {
            case .system:
                VisualEffectBackground()
            case .color:
                RoundedRectangle(cornerRadius: 16)
                    .fill(ColorUtils.fromHex(dockBackgroundColorHex))
            case .transparent:
                Color.clear
            }
        }
    }

    private func removeShortcut(_ shortcut: AppShortcut) {
        AppShortcutStore.deleteIcon(named: shortcut.iconFileName)
        shortcuts.removeAll { $0.id == shortcut.id }
        AppShortcutStore.save(shortcuts)
    }

    private func updateShortcut(_ updated: AppShortcut) {
        if let index = shortcuts.firstIndex(where: { $0.id == updated.id }) {
            shortcuts[index] = updated
            AppShortcutStore.save(shortcuts)
            // we need to 'refresh' the icons in the dock here
        }
    }

    private func dragStart(shortcut: AppShortcut, icon: Image?) {
        let originalIndex = shortcuts.firstIndex(where: { $0.id == shortcut.id }) ?? 0
        draggingID = shortcut.id
        draggingShortcut = shortcut
        targetIndex = originalIndex
        var display = shortcuts.map { Optional($0) }
        display[originalIndex] = nil
        displayShortcuts = display

        // Set initial drag position from current cursor location.
        // Find the dock window by checking which visible window contains the cursor.
        let screenPt = NSEvent.mouseLocation
        if let window = NSApp.windows.first(where: { $0.isVisible && $0.frame.contains(screenPt) }) {
            let windowPt = window.convertPoint(fromScreen: screenPt)
            dragPosition = CGPoint(x: windowPt.x, y: windowContentHeight - windowPt.y)
        }

        draggingIcon = icon
        isShaking = true

        // NSEvent monitor takes over position tracking once the button
        // leaves the view hierarchy (SwiftUI cancels its DragGesture).
        ContentView.dragMonitorToken = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDragged, .leftMouseUp]
        ) { event in
            if event.type == .leftMouseDragged {
                let nsLoc = event.locationInWindow
                let pt = CGPoint(x: nsLoc.x, y: self.windowContentHeight - nsLoc.y)
                self.dragChanged(to: pt)
            } else if event.type == .leftMouseUp {
                self.dragEnd()
            }
            return event
        }
    }

    private func dragChanged(to position: CGPoint) {
        dragPosition = position
        // Shortcuts start at: 10pt padding + weather widget width + spacing (if shown)
        let dockOriginX: CGFloat = 10 + (showWeatherWidget
            ? DockWidget<EmptyView>.cellSize * CGFloat(WeatherWidget.cellCount) + hstackItemSpacing
            : 0)
        let localX = position.x - dockOriginX
        let rawIndex = Int((localX + DockWidget<EmptyView>.cellSize / 4) / DockWidget<EmptyView>.cellSize)
        let newIndex = max(0, min(shortcuts.count - 1, rawIndex))
        guard newIndex != targetIndex else { return }
        targetIndex = newIndex
        guard let dragging = draggingShortcut else { return }
        var display = shortcuts.filter { $0.id != dragging.id }.map { Optional($0) }
        display.insert(nil, at: targetIndex)
        displayShortcuts = display
    }

    private func dragEnd() {
        guard draggingID != nil else { return }
        if let token = ContentView.dragMonitorToken {
            NSEvent.removeMonitor(token)
            ContentView.dragMonitorToken = nil
        }

        // Commit the reorder: place the dragged shortcut into the placeholder slot
        if let dragging = draggingShortcut, !displayShortcuts.isEmpty {
            let originalIndex = shortcuts.firstIndex(where: { $0.id == dragging.id })
            if targetIndex != originalIndex {
                var committed = displayShortcuts
                committed[targetIndex] = dragging
                shortcuts = committed.compactMap { $0 }
                AppShortcutStore.save(shortcuts)
            }
        }

        isShaking = false
        draggingID = nil
        draggingShortcut = nil
        draggingIcon = nil
        dragPosition = .zero
        displayShortcuts = []
        targetIndex = 0
    }
}

private let hstackItemSpacing: CGFloat = 8

private struct DragGhostIcon: View {
    let icon: Image?
    let isShaking: Bool

    @State private var angle: Double = 0

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.gray.opacity(0.3))
            if let icon {
                icon
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(4)
            }
        }
        .frame(width: 64, height: 64)
        .scaleEffect(1.05)
        .rotationEffect(.degrees(angle))
        .shadow(radius: 8, y: 4)
        .task(id: isShaking) {
            guard isShaking else {
                withAnimation(.easeOut(duration: 0.15)) { angle = 0 }
                return
            }
            while !Task.isCancelled {
                withAnimation(.easeInOut(duration: 0.1)) { angle = 3.0 }
                try? await Task.sleep(for: .milliseconds(100))
                withAnimation(.easeInOut(duration: 0.1)) { angle = -3.0 }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }
}

#Preview {
    ContentView()
}
