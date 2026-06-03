import AppKit
import SwiftUI

@Observable
final class DragCoordinator {

    var isDraggingFromFolder: Bool = false
    var sourceShortcut: AppShortcut? = nil
    var sourceFolder: AppFolder? = nil
    var dropIndex: Int? = nil
    var isOverDock: Bool = false
    var dropCommitted: Bool = false

    private var monitorToken: Any?
    private weak var cachedDockPanel: NSPanel?
    private var dockItemCount: Int = 0
    private var dragStartPoint: CGPoint = .zero
    private var hasStartedShaking: Bool = false

    private let cellSize: CGFloat = 64
    private let cellStep: CGFloat = 72   // cellSize + 8pt spacing
    private let dockPadding: CGFloat = 10
    private let shakeThreshold: CGFloat = 4

    // MARK: - Public API

    func beginDrag(shortcut: AppShortcut, folder: AppFolder, icon: Image?,
                   at screenPoint: CGPoint, itemCount: Int) {
        sourceShortcut = shortcut
        sourceFolder = folder
        dockItemCount = itemCount
        dragStartPoint = screenPoint
        cachedDockPanel = NSApp.windows.first(where: { $0 is DeskMatPanel }) as? NSPanel
        hasStartedShaking = false
        isDraggingFromFolder = true
        isOverDock = false
        dropIndex = nil

        DragGhostPanel.shared.show(icon: icon, at: screenPoint)

        monitorToken = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDragged, .leftMouseUp]
        ) { [weak self] event in
            guard let self else { return event }
            if event.type == .leftMouseDragged {
                self.handleMouseMoved(to: NSEvent.mouseLocation)
            } else if event.type == .leftMouseUp {
                self.endDrag()
            }
            return event
        }
    }

    func endDrag() {
        if let token = monitorToken {
            NSEvent.removeMonitor(token)
            monitorToken = nil
        }
        DragGhostPanel.shared.hide()
        // Reset display flag first so the dock returns to normal before the mutation lands
        isDraggingFromFolder = false

        if isOverDock, dropIndex != nil {
            // Signal ContentView to commit; sourceShortcut/sourceFolder/dropIndex stay set
            dropCommitted = true
        } else {
            FolderExpansionPanel.shared.dismiss()
            resetAfterDrop()
        }
    }

    func resetAfterDrop() {
        sourceShortcut = nil
        sourceFolder = nil
        dropIndex = nil
        isOverDock = false
        dropCommitted = false
        hasStartedShaking = false
        dragStartPoint = .zero
        cachedDockPanel = nil
    }

    // MARK: - Private

    private func handleMouseMoved(to screenPoint: CGPoint) {
        DragGhostPanel.shared.move(to: screenPoint)

        if !hasStartedShaking {
            let dx = screenPoint.x - dragStartPoint.x
            let dy = screenPoint.y - dragStartPoint.y
            if dx * dx + dy * dy > shakeThreshold * shakeThreshold {
                hasStartedShaking = true
                DragGhostPanel.shared.startShaking()
            }
        }

        guard let dockPanel = cachedDockPanel else {
            isOverDock = false
            dropIndex = nil
            return
        }

        isOverDock = dockPanel.frame.contains(screenPoint)

        if isOverDock {
            let localX = screenPoint.x - dockPanel.frame.minX - dockPadding
            let rawIndex = Int((localX - cellSize / 2 + cellStep / 2) / cellStep)
            dropIndex = max(0, min(dockItemCount, rawIndex))
        } else {
            dropIndex = nil
        }
    }
}
