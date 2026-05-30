import SwiftUI
import AppKit

struct ContentView: View {
    @Environment(LicenseManager.self) private var entitlements
    @Environment(WindowStateService.self) private var windowState
    @State private var items: [DockItem] = AppShortcutStore.load()
    @AppStorage("showWeatherWidget") private var showWeatherWidget = false
    @AppStorage("showClockWidget") private var showClockWidget = false
    @AppStorage("showImageWidget") private var showImageWidget = false
    @AppStorage("showLEDBoard") private var showLEDBoard = false
    @AppStorage("showSystemWidget") private var showSystemWidget = false
    @AppStorage("dockBackground") private var dockBackground: DockBackground = .system
    @AppStorage("reactiveStyle") private var reactiveStyle: ReactiveStyle = .none
    @AppStorage("limitReactiveFPS") private var limitReactiveFPS: Bool = true
    @AppStorage("dockBackgroundColorHex") private var dockBackgroundColorHex: String = "#000000ff"
    @AppStorage("dockCornerRadius") private var dockCornerRadius: Double = 16
    @AppStorage("showWidgetDivider") private var showWidgetDivider = true

    @State private var openFolderID: UUID?

    // Drag-to-reorder state
    @State private var draggingID: UUID? = nil
    @State private var draggingItem: DockItem? = nil
    @State private var draggingIcon: Image? = nil
    @State private var dragPosition: CGPoint = .zero
    @State private var displayItems: [DockItem?] = []
    @State private var targetIndex: Int = 0
    @State private var dropTargetID: UUID? = nil
    @State private var mergeConfirmed: Bool = false
    @State private var windowContentHeight: CGFloat = 0
    @State private var isShaking: Bool = false
    private static var dragMonitorToken: Any?
    private static var dwellWorkItem: DispatchWorkItem?

    var body: some View {
        ZStack {
            HStack {
                if draggingID != nil {
                    ForEach(displayItems.indices, id: \.self) { i in
                        if let item = displayItems[i] {
                            dockItemView(for: item, isReordering: true)
                        } else {
                            Color.clear.frame(width: 64, height: 64)
                        }
                    }
                } else {
                    ForEach(items) { item in
                        dockItemView(for: item, isReordering: false)
                    }
                }

                if showWidgetDivider && !items.isEmpty && anyWidgetVisible {
                    Rectangle()
                        .fill(.white.opacity(0.25))
                        .frame(width: 1, height: 56)
                        .padding(.horizontal, 4)
                }

                if entitlements.isPro && showWeatherWidget {
                    WeatherWidget()
                }

                if entitlements.isPro && showImageWidget {
                    ImageWidget()
                }

                if entitlements.isPro && showLEDBoard {
                    LEDBoardWidget()
                }

                if entitlements.isPro && showClockWidget {
                    ClockWidget()
                }

                if entitlements.isPro && showSystemWidget {
                    SystemWidget()
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .animation(.spring(duration: 0.2), value: displayItems.map { $0?.id })
            .contextMenu {
                Button(Strings.Menu.addShortcut) {
                    NotificationCenter.default.post(name: .addShortcut, object: nil)
                }
                Button(Strings.Menu.newFolder) {
                    NotificationCenter.default.post(name: .addFolder, object: nil)
                }
                Divider()
                Button(Strings.Menu.exportDock) {
                    NotificationCenter.default.post(name: .exportDock, object: nil)
                }
                .disabled(!entitlements.isPro)
                Button(Strings.Menu.importDock) {
                    NotificationCenter.default.post(name: .importDock, object: nil)
                }
                .disabled(!entitlements.isPro)
                Divider()
                Button(Strings.Menu.settings) {
                    NotificationCenter.default.post(name: .openSettings, object: nil)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .shortcutAdded)) { notification in
                if let newShortcut = notification.object as? AppShortcut {
                    items.append(.shortcut(newShortcut))
                    AppShortcutStore.save(items)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .shortcutEdited)) { notification in
                if let updated = notification.object as? AppShortcut {
                    updateShortcut(updated)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .folderAdded)) { notification in
                if let newFolder = notification.object as? AppFolder {
                    items.append(.folder(newFolder))
                    AppShortcutStore.save(items)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .folderEdited)) { notification in
                if let updated = notification.object as? AppFolder {
                    updateFolder(updated)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .dockImported)) { notification in
                if let imported = notification.object as? [DockItem] {
                    items = imported
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .folderExpansionDismissed)) { _ in
                openFolderID = nil
            }

            if draggingItem != nil {
                DragGhostIcon(icon: draggingIcon, isShaking: isShaking, showFolderBadge: mergeConfirmed)
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
                RoundedRectangle(cornerRadius: dockCornerRadius)
                    .fill(ColorUtils.fromHex(dockBackgroundColorHex))
            case .transparent:
                Color.clear
            case .reactive:
                if reactiveStyle != .none {
                    ReactiveBackgroundRepresentable(style: reactiveStyle, cornerRadius: dockCornerRadius, limitFPS: limitReactiveFPS)
                } else {
                    Color.clear
                }
            }
        }
    }

    // MARK: - Item View Builder

    @ViewBuilder
    private func dockItemView(for item: DockItem, isReordering: Bool) -> some View {
        let isTarget = dropTargetID == item.id && mergeConfirmed

        Group {
            switch item {
            case .shortcut(let shortcut):
                AppShortcutButton(
                    shortcut: shortcut,
                    onRemove: { removeItem(item) },
                    isReordering: isReordering,
                    onDragStart: { icon in dragStart(item: item, icon: icon) }
                )
            case .folder(let folder):
                FolderButton(
                    folder: folder,
                    isReordering: isReordering,
                    isOpen: openFolderID == folder.id,
                    onRemove: { removeItem(item) },
                    onEdit: { NotificationCenter.default.post(name: .editFolder, object: folder) },
                    onDragStart: { icon in dragStart(item: item, icon: icon) },
                    onOpen: { f, frame in openFolder(f, buttonFrame: frame) }
                )
            }
        }
        .overlay(alignment: .top) {
            if isTarget {
                DropTargetRing()
                    .frame(width: 64, height: 64)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isTarget)
    }

    // MARK: - Folder Expansion

    private func openFolder(_ folder: AppFolder, buttonFrame: CGRect) {
        if FolderExpansionPanel.shared.openFolderID == folder.id {
            FolderExpansionPanel.shared.dismiss()
            return
        }
        guard let dockPanel = NSApp.windows.first(where: { $0 is DeskMatPanel }) else { return }
        let screenCenterX = dockPanel.frame.minX + buttonFrame.midX
        let dockTopY      = dockPanel.frame.maxY
        openFolderID = folder.id
        FolderExpansionPanel.shared.show(
            folder: folder, centeredAt: screenCenterX, dockTopY: dockTopY,
            windowState: windowState, entitlements: entitlements,
            dockBackground: dockBackground, dockBackgroundColorHex: dockBackgroundColorHex,
            dockCornerRadius: dockCornerRadius, reactiveStyle: reactiveStyle,
            limitReactiveFPS: limitReactiveFPS
        )
    }

    // MARK: - Helpers

    private var anyWidgetVisible: Bool {
        entitlements.isPro && (showWeatherWidget || showImageWidget || showLEDBoard || showClockWidget || showSystemWidget)
    }

    private func removeItem(_ item: DockItem) {
        AppShortcutStore.deleteIcons(for: item)
        items.removeAll { $0.id == item.id }
        AppShortcutStore.save(items)
    }

    private func updateShortcut(_ updated: AppShortcut) {
        // Top-level shortcut
        if let index = items.firstIndex(where: { $0.id == updated.id }) {
            items[index] = .shortcut(updated)
            AppShortcutStore.save(items)
            return
        }
        // Shortcut nested inside a folder
        for (i, item) in items.enumerated() {
            if case .folder(var folder) = item,
               let j = folder.shortcuts.firstIndex(where: { $0.id == updated.id }) {
                folder.shortcuts[j] = updated
                items[i] = .folder(folder)
                AppShortcutStore.save(items)
                return
            }
        }
    }

    private func updateFolder(_ updated: AppFolder) {
        if let index = items.firstIndex(where: { $0.id == updated.id }) {
            items[index] = .folder(updated)
            AppShortcutStore.save(items)
        }
    }

    // MARK: - Drag-to-Reorder

    private func dragStart(item: DockItem, icon: Image?) {
        let originalIndex = items.firstIndex(where: { $0.id == item.id }) ?? 0
        (NSApp.delegate as? AppDelegate)?.isDragging = true
        draggingID = item.id
        draggingItem = item
        targetIndex = originalIndex
        var display = items.map { Optional($0) }
        display[originalIndex] = nil
        displayItems = display

        let screenPt = NSEvent.mouseLocation
        if let window = NSApp.windows.first(where: { $0.isVisible && $0.frame.contains(screenPt) }) {
            let windowPt = window.convertPoint(fromScreen: screenPt)
            dragPosition = CGPoint(x: windowPt.x, y: windowContentHeight - windowPt.y)
        }

        draggingIcon = icon
        isShaking = true

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

    private enum DragMode {
        case reorder(Int)
        case merge(UUID)
    }

    private func computeDragMode(localX: CGFloat) -> DragMode {
        guard let dragging = draggingItem else { return .reorder(0) }
        let cellSize = DockWidget<EmptyView>.cellSize
        let step = cellSize + hstackItemSpacing
        let mergeThreshold = cellSize * 0.6

        // Compute reorder index first so we know where the gap sits
        let rawIndex = Int((localX - cellSize / 2 + step / 2) / step)
        let reorderIndex = max(0, min(items.count - 1, rawIndex))

        // Check merge using gap-adjusted visual centers
        let remaining = items.filter { $0.id != dragging.id }
        for (j, item) in remaining.enumerated() {
            let displayIndex = j < reorderIndex ? j : j + 1
            let centerX = cellSize / 2 + CGFloat(displayIndex) * step
            if abs(localX - centerX) < mergeThreshold {
                return .merge(item.id)
            }
        }

        return .reorder(reorderIndex)
    }

    private func scheduleDwell(for targetID: UUID) {
        ContentView.dwellWorkItem?.cancel()
        let work = DispatchWorkItem { self.mergeConfirmed = true }
        ContentView.dwellWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    private func cancelDwell() {
        ContentView.dwellWorkItem?.cancel()
        ContentView.dwellWorkItem = nil
        mergeConfirmed = false
    }

    private func dragChanged(to position: CGPoint) {
        dragPosition = position
        let localX = position.x - 10 // subtract horizontal padding
        guard let dragging = draggingItem else { return }

        switch computeDragMode(localX: localX) {
        case .merge(let targetID):
            if targetID != dropTargetID {
                cancelDwell()
                scheduleDwell(for: targetID)
            }
            dropTargetID = targetID
            targetIndex = -1
            displayItems = items.filter { $0.id != dragging.id }.map { Optional($0) }

        case .reorder(let newIndex):
            cancelDwell()
            dropTargetID = nil
            guard newIndex != targetIndex else { return }
            targetIndex = newIndex
            var display = items.filter { $0.id != dragging.id }.map { Optional($0) }
            display.insert(nil, at: targetIndex)
            displayItems = display
        }
    }

    private func performMerge(dragging: DockItem, targetID: UUID) {
        guard let targetItem = items.first(where: { $0.id == targetID }),
              let dragIdx   = items.firstIndex(where: { $0.id == dragging.id }),
              let targetIdx = items.firstIndex(where: { $0.id == targetID }) else { return }

        let insertAt = min(dragIdx, targetIdx)

        let resultFolder: AppFolder

        switch (dragging, targetItem) {
        case (.shortcut(let ds), .shortcut(let ts)):
            resultFolder = AppFolder(name: "New Folder", shortcuts: [ds, ts])

        case (.shortcut(let ds), .folder(var tf)):
            if !tf.shortcuts.contains(where: { $0.bundleIdentifier == ds.bundleIdentifier }) {
                tf.shortcuts.append(ds)
            }
            resultFolder = tf

        case (.folder(var df), .shortcut(let ts)):
            if !df.shortcuts.contains(where: { $0.bundleIdentifier == ts.bundleIdentifier }) {
                df.shortcuts.append(ts)
            }
            resultFolder = df

        case (.folder(var df), .folder(let tf)):
            for shortcut in tf.shortcuts where !df.shortcuts.contains(where: { $0.bundleIdentifier == shortcut.bundleIdentifier }) {
                df.shortcuts.append(shortcut)
            }
            if let icon = tf.iconFileName { AppShortcutStore.deleteIcon(named: icon) }
            resultFolder = df
        }

        var updated = items.filter { $0.id != dragging.id && $0.id != targetID }
        updated.insert(.folder(resultFolder), at: min(insertAt, updated.count))
        items = updated
        AppShortcutStore.save(items)
    }

    private func dragEnd() {
        guard draggingID != nil else { return }
        if let token = ContentView.dragMonitorToken {
            NSEvent.removeMonitor(token)
            ContentView.dragMonitorToken = nil
        }

        if let dragging = draggingItem, let targetID = dropTargetID, mergeConfirmed {
            performMerge(dragging: dragging, targetID: targetID)
        } else if dropTargetID == nil, let dragging = draggingItem, !displayItems.isEmpty {
            let originalIndex = items.firstIndex(where: { $0.id == dragging.id })
            if targetIndex != originalIndex {
                var committed = displayItems
                committed[targetIndex] = dragging
                items = committed.compactMap { $0 }
                AppShortcutStore.save(items)
            }
        }

        cancelDwell()
        (NSApp.delegate as? AppDelegate)?.isDragging = false
        isShaking = false
        draggingID = nil
        draggingItem = nil
        draggingIcon = nil
        dragPosition = .zero
        displayItems = []
        targetIndex = 0
        dropTargetID = nil
    }
}

private let hstackItemSpacing: CGFloat = 8

private struct DragGhostIcon: View {
    let icon: Image?
    let isShaking: Bool
    let showFolderBadge: Bool

    @State private var angle: Double = 0

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
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

            if showFolderBadge {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 20))
                    .foregroundStyle(.white, .blue)
                    .offset(x: 6, y: 6)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .scaleEffect(1.05)
        .rotationEffect(.degrees(angle))
        .shadow(radius: 8, y: 4)
        .animation(.spring(duration: 0.25), value: showFolderBadge)
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

private struct DropTargetRing: View {
    @State private var scale: CGFloat = 1.0
    @State private var opacity: Double = 0.8

    var body: some View {
        RoundedRectangle(cornerRadius: 10)
            .stroke(Color.white.opacity(opacity), lineWidth: 2.5)
            .scaleEffect(scale)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) {
                    scale = 1.1
                    opacity = 0.25
                }
            }
    }
}

#Preview {
    ContentView()
        .environment(LicenseManager())
}
