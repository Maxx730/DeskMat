import SwiftUI
import AppKit

struct ContentView: View {
    @Environment(LicenseManager.self) private var entitlements
    @Environment(WindowStateService.self) private var windowState
    @Environment(DragCoordinator.self) private var dragCoordinator
    @State private var items: [DockItem] = AppShortcutStore.load()
    @AppStorage("showWeatherWidget") private var showWeatherWidget = false
    @AppStorage("showClockWidget") private var showClockWidget = false
    @AppStorage("showImageWidget") private var showImageWidget = false
    @AppStorage("showLEDBoard") private var showLEDBoard = false
    @AppStorage("showSystemWidget") private var showSystemWidget = false
    @AppStorage("showEveWidget") private var showEveWidget = false
    @AppStorage("showWebFrameWidget") private var showWebFrameWidget = false
    @AppStorage("showTestWidget") private var showTestWidget = false
    @AppStorage("dockBackground") private var dockBackground: DockBackground = .system
    @AppStorage("reactiveStyle") private var reactiveStyle: ReactiveStyle = .none
    @AppStorage("limitReactiveFPS") private var limitReactiveFPS: Bool = true
    @AppStorage("dockBackgroundColorHex") private var dockBackgroundColorHex: String = "#000000ff"
    @AppStorage("dockCornerRadius") private var dockCornerRadius: Double = 16
    @AppStorage("dockStrokeEnabled") private var dockStrokeEnabled: Bool = false
    @AppStorage("dockStrokeColorHex") private var dockStrokeColorHex: String = "#FFFFFF80"
    @AppStorage("dockStrokeWidth") private var dockStrokeWidth: Double = 1.5
    @AppStorage("showWidgetDivider") private var showWidgetDivider = true

    @State private var openFolderID: UUID?
    @State private var folderPendingDelete: DockItem? = nil

    // Drag-to-reorder state
    @State private var draggingID: UUID? = nil
    @State private var draggingItem: DockItem? = nil
    @State private var displayItems: [DockItem?] = []
    @State private var targetIndex: Int = 0
    @State private var dropTargetID: UUID? = nil
    @State private var mergeConfirmed: Bool = false
    @State private var windowContentHeight: CGFloat = 0
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
                            DropGapSlot()
                        }
                    }
                } else if dragCoordinator.isDraggingFromFolder && dragCoordinator.isOverDock,
                          let dropIdx = dragCoordinator.dropIndex {
                    let crossItems = crossDisplayItems(dropAt: dropIdx)
                    ForEach(crossItems.indices, id: \.self) { i in
                        if let item = crossItems[i] {
                            dockItemView(for: item, isReordering: false)
                        } else {
                            DropGapSlot()
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

                if entitlements.isPro && showEveWidget {
                    EveWidget()
                }

                if entitlements.isPro && showWebFrameWidget {
                    WebFrameWidget()
                }

                // Phase 2 temporary wiring — replaced with @AppStorage gate in Phase 4
                MediaControlWidget()

                if showTestWidget {
                    TestWidget()
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .animation(.spring(duration: 0.2), value: displayItems.map { $0?.id })
            .animation(.spring(duration: 0.2), value: dragCoordinator.dropIndex)
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
        .overlay {
            if dockBackground == .color && dockStrokeEnabled {
                RoundedRectangle(cornerRadius: dockCornerRadius)
                    .strokeBorder(
                        ColorUtils.fromHex(dockStrokeColorHex),
                        lineWidth: dockStrokeWidth
                    )
            }
        }
        .onChange(of: dragCoordinator.dropCommitted) { _, committed in
            guard committed else { return }
            if let shortcut = dragCoordinator.sourceShortcut,
               let folder   = dragCoordinator.sourceFolder,
               let index    = dragCoordinator.dropIndex {
                commitFolderDrop(shortcut: shortcut, folder: folder, at: index)
            }
            dragCoordinator.resetAfterDrop()
        }
        .onChange(of: folderPendingDelete) { _, item in
            guard let item else { return }
            // Defer runModal() so it fires after SwiftUI's update cycle completes,
            // avoiding a nested NSRunLoop inside an onChange modifier.
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = Strings.FolderDelete.alertTitle(self.folderDeleteName)  // never empty — returns "Folder" as fallback
                alert.informativeText = self.folderDeleteMessage
                alert.addButton(withTitle: Strings.FolderDelete.confirm)
                alert.addButton(withTitle: Strings.Common.cancel)
                alert.buttons[0].hasDestructiveAction = true
                if alert.runModal() == .alertFirstButtonReturn {
                    self.removeItem(item)
                }
                self.folderPendingDelete = nil
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
                    onRemove: { folderPendingDelete = item },
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
        .animation(.easeInOut(duration: 0.1), value: isTarget)
    }

    // MARK: - Folder Delete Confirmation

    private var folderDeleteName: String {
        if case .folder(let f) = folderPendingDelete { return f.name }
        return "Folder"
    }

    private var folderDeleteMessage: String {
        guard case .folder(let f) = folderPendingDelete else { return "" }
        let count = f.shortcuts.count
        if count == 0 { return Strings.FolderDelete.emptyMessage }
        return Strings.FolderDelete.message(count: count)
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
            dockCornerRadius: dockCornerRadius,
            onItemDragStart: { [dragCoordinator, itemCount = items.count] shortcut, sourceFolder, icon in
                FolderExpansionPanel.shared.dismiss()
                dragCoordinator.beginDrag(
                    shortcut: shortcut, folder: sourceFolder, icon: icon,
                    at: NSEvent.mouseLocation, itemCount: itemCount
                )
            }
        )
    }

    // MARK: - Helpers

    private func crossDisplayItems(dropAt index: Int) -> [DockItem?] {
        var display = items.map { Optional($0) }
        let clamped = max(0, min(display.count, index))
        display.insert(nil, at: clamped)
        return display
    }

    private var anyWidgetVisible: Bool {
        showTestWidget || (entitlements.isPro && (showWeatherWidget || showImageWidget || showLEDBoard || showClockWidget || showSystemWidget || showEveWidget || showWebFrameWidget))
    }

    private func commitFolderDrop(shortcut: AppShortcut, folder: AppFolder, at dropIndex: Int) {
        guard let folderItemIndex = items.firstIndex(where: {
            if case .folder(let f) = $0 { return f.id == folder.id }
            return false
        }) else { return }

        guard case .folder(var sourceFolder) = items[folderItemIndex] else { return }
        sourceFolder.shortcuts.removeAll { $0.id == shortcut.id }

        if sourceFolder.shortcuts.isEmpty {
            items.remove(at: folderItemIndex)
            let adjustedIndex = folderItemIndex < dropIndex ? dropIndex - 1 : dropIndex
            items.insert(.shortcut(shortcut), at: min(adjustedIndex, items.count))
        } else {
            items[folderItemIndex] = .folder(sourceFolder)
            items.insert(.shortcut(shortcut), at: min(dropIndex, items.count))
        }

        AppShortcutStore.save(items)
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
        DragGhostPanel.shared.show(icon: icon, at: screenPt)
        DragGhostPanel.shared.startShaking()

        ContentView.dragMonitorToken = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDragged, .leftMouseUp]
        ) { [weak dockPanel = NSApp.windows.first(where: { $0 is DeskMatPanel })] event in
            if event.type == .leftMouseDragged {
                // Use screen → dock conversion so the ghost panel's window level
                // doesn't corrupt event.locationInWindow coordinates.
                let screenPt = NSEvent.mouseLocation
                if let dock = dockPanel {
                    let windowPt = dock.convertPoint(fromScreen: screenPt)
                    let pt = CGPoint(x: windowPt.x, y: self.windowContentHeight - windowPt.y)
                    self.dragChanged(to: pt)
                }
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
        let mergeThreshold = cellSize * 0.9

        let rawIndex = Int((localX - cellSize / 2 + step / 2) / step)
        let reorderIndex = max(0, min(items.count - 1, rawIndex))

        // Compute each item's visual center given the current gap position, then
        // check for merge. displayItems is intentionally NOT updated in the merge
        // branch of dragChanged, so the gap stays fixed while the user dwells —
        // this prevents the visual jump that was the observable part of the flicker.
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
        let work = DispatchWorkItem {
            self.mergeConfirmed = true
            DragGhostPanel.shared.setFolderBadge(true)
        }
        ContentView.dwellWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    private func cancelDwell() {
        ContentView.dwellWorkItem?.cancel()
        ContentView.dwellWorkItem = nil
        mergeConfirmed = false
        DragGhostPanel.shared.setFolderBadge(false)
    }

    private func dragChanged(to position: CGPoint) {
        DragGhostPanel.shared.move(to: NSEvent.mouseLocation)
        let localX = position.x - 10 // subtract horizontal padding
        guard let dragging = draggingItem else { return }

        switch computeDragMode(localX: localX) {
        case .merge(let targetID):
            if targetID != dropTargetID {
                cancelDwell()
                scheduleDwell(for: targetID)
            }
            dropTargetID = targetID
            // targetIndex intentionally not reset — its current value is what
            // computeDragMode uses for stable item center calculation.
            // displayItems intentionally not updated — keeps items at their
            // reorder positions so the gap doesn't jump mid-hover.

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
        DragGhostPanel.shared.hide()
        (NSApp.delegate as? AppDelegate)?.isDragging = false
        draggingID = nil
        draggingItem = nil
        displayItems = []
        targetIndex = 0
        dropTargetID = nil
    }
}

private let hstackItemSpacing: CGFloat = 8

struct DragGhostIcon: View {
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

private struct DropGapSlot: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 10)
            .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
            .foregroundStyle(.white.opacity(0.4))
            .frame(width: 64, height: 64)
    }
}

private struct DropTargetRing: View {
    @State private var scale: CGFloat = 1.0
    @State private var opacity: Double = 0.8

    var body: some View {
        RoundedRectangle(cornerRadius: 12)
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
