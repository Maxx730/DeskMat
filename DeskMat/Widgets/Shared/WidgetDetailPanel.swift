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

    func open<Content: View>(@ViewBuilder content: () -> Content) {
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
        centerOnScreen()

        alphaValue = 0
        orderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().alphaValue = 1
        }

        installEscapeMonitor()
    }

    func dismiss() {
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
            if event.keyCode == 53 { self?.dismiss(); return nil }
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

    private func centerOnScreen() {
        let screenFrame = NSScreen.main?.visibleFrame ?? .zero
        let origin = CGPoint(
            x: screenFrame.midX - frame.width  / 2,
            y: screenFrame.midY - frame.height / 2
        )
        setFrameOrigin(origin)
    }
}

// MARK: - Default panel background

struct MaterialPanelBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 12).fill(.regularMaterial)
    }
}

// MARK: - Shared chrome

struct WidgetPanelChrome<Content: View, Background: View>: View {
    let title: String
    let onClose: () -> Void
    var darkTitle: Bool = false
    var showTitle: Bool = true
    @ViewBuilder let background: () -> Background
    @ViewBuilder let content: () -> Content

    @State private var isHoveringClose = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button(action: onClose) {
                    ZStack {
                        Circle()
                            .fill(isHoveringClose ? Color(red: 0.6, green: 0.08, blue: 0.08) : Color(nsColor: .systemRed))
                            .frame(width: 12, height: 12)
                        if isHoveringClose {
                            Image(systemName: "xmark")
                                .font(.system(size: 6, weight: .bold))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                    }
                }
                .buttonStyle(.plain)
                .onHover { isHoveringClose = $0 }
                .animation(.easeInOut(duration: 0.1), value: isHoveringClose)

                if showTitle {
                    Text(title)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(darkTitle ? Color.black.opacity(0.6) : Color.secondary)
                }

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)

            content()
        }
        .background { background() }
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

extension WidgetPanelChrome where Background == MaterialPanelBackground {
    init(
        title: String,
        onClose: @escaping () -> Void,
        darkTitle: Bool = false,
        showTitle: Bool = true,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(title: title, onClose: onClose, darkTitle: darkTitle, showTitle: showTitle, background: { MaterialPanelBackground() }, content: content)
    }
}
