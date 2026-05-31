import AppKit
import SwiftUI
import QuartzCore

final class FolderExpansionPanel: NSPanel {

    static let shared = FolderExpansionPanel()

    private var hostingView: FirstMouseHostingView<FolderExpansionView>?
    private var targetFrame: NSRect = .zero
    private var isDismissing = false
    private(set) var openFolderID: UUID?

    private var outsideClickMonitor: Any?
    private var escapeKeyMonitor: Any?

    private init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        isMovable = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    override var canBecomeKey: Bool { true }

    // MARK: - Show / Dismiss

    func show(folder: AppFolder, centeredAt screenX: CGFloat, dockTopY: CGFloat,
              windowState: WindowStateService, entitlements: LicenseManager,
              dockBackground: DockBackground, dockBackgroundColorHex: String,
              dockCornerRadius: Double) {
        isDismissing = false
        openFolderID = folder.id

        let view = FolderExpansionView(
            folder: folder,
            onLaunch: { [weak self] in self?.dismiss() },
            windowState: windowState,
            entitlements: entitlements,
            dockBackground: dockBackground,
            dockBackgroundColorHex: dockBackgroundColorHex,
            dockCornerRadius: dockCornerRadius
        )

        if let hv = hostingView {
            hv.rootView = view
        } else {
            let hv = FirstMouseHostingView(rootView: view)
            hv.autoresizingMask = [.width, .height]
            contentView = hv
            hostingView = hv
        }

        sizeToFitContent()
        position(centeredAt: screenX, dockTopY: dockTopY)
        targetFrame = frame

        var startFrame = targetFrame
        startFrame.origin.y -= 12
        setFrame(startFrame, display: false)
        alphaValue = 0
        orderFront(nil)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().alphaValue = 1
            self.animator().setFrame(self.targetFrame, display: true)
        }

        installMonitors()
    }

    func dismiss() {
        guard !isDismissing else { return }
        isDismissing = true
        removeMonitors()

        var endFrame = frame
        endFrame.origin.y -= 12

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            self.animator().alphaValue = 0
            self.animator().setFrame(endFrame, display: true)
        } completionHandler: { [weak self] in
            self?.orderOut(nil)
            self?.alphaValue = 1
            self?.isDismissing = false
            self?.openFolderID = nil
            NotificationCenter.default.post(name: .folderExpansionDismissed, object: nil)
        }
    }

    // MARK: - Event Monitors

    private func installMonitors() {
        removeMonitors()

        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            guard let self else { return }
            if !self.frame.contains(NSEvent.mouseLocation) {
                self.dismiss()
            }
        }

        escapeKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.dismiss()
                return nil
            }
            return event
        }
    }

    private func removeMonitors() {
        if let m = outsideClickMonitor { NSEvent.removeMonitor(m); outsideClickMonitor = nil }
        if let m = escapeKeyMonitor    { NSEvent.removeMonitor(m); escapeKeyMonitor    = nil }
    }

    // MARK: - Layout

    private func sizeToFitContent() {
        guard let hv = hostingView else { return }
        hv.layout()
        var size = hv.fittingSize
        if size.width  <= 0 { size.width  = 80 }
        if size.height <= 0 { size.height = 80 }
        setContentSize(size)
    }

    private func position(centeredAt screenX: CGFloat, dockTopY: CGFloat) {
        var origin = frame.origin
        origin.x = screenX - frame.width / 2
        origin.y = dockTopY + 8
        setFrameOrigin(origin)
    }
}
