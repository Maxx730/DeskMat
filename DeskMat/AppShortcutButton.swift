import SwiftUI
import AppKit
import ApplicationServices


struct AppShortcutButton: View {
    let shortcut: AppShortcut
    let onRemove: () -> Void
    let isReordering: Bool
    let onDragStart: (Image?) -> Void

    @AppStorage("showLabels") private var showLabels = true
    @AppStorage("showHoverLabel") private var hoverLabelEnabled = true
    @AppStorage("showIconBackground") private var showIconBackground = true
    @AppStorage("hoverSize") private var hoverSize: HoverSize = .small
    @AppStorage("hoverAnimation") private var hoverAnimation: HoverAnimation = .bounce
    @AppStorage("finderDefaultDirectory") private var finderDefaultDirectory = "~/"

    @Environment(WindowStateService.self) private var windowState

    @State private var isHovering = false
    @State private var showHoverLabel = false
    @State private var bobScale: Double = 1.0
    @State private var avgColor: Color = .gray
    @State private var cachedIcon: Image?
    @State private var cachedIconFull: Image?
    @State private var isFrontmost = false

    private var windowCount: Int { windowState.info(for: shortcut.bundleIdentifier).count }
    private var hasMinimizedWindows: Bool { windowState.info(for: shortcut.bundleIdentifier).hasMinimized }

    @State private var jiggleAngle: Double = 0
    @State private var suppressNextTap = false
    @State private var launchFlashOpacity: Double = 0
    @State private var isLaunching = false
    @State private var hoverStartDate: Date? = nil

    var body: some View {
        VStack(spacing: 10) {
            ZStack(alignment: .bottom) {
                // Icon + all hover effects (scale, rotation, shader, flash)
                ZStack {
                    if showIconBackground {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(avgColor)
                        (cachedIcon ?? Image(systemName: "questionmark.app"))
                        if isFrontmost {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(ColorUtils.brightenedHSV(avgColor), lineWidth: 2)
                                .padding(1)
                        }
                    } else {
                        if let icon = cachedIconFull {
                            icon
                        } else {
                            Image(systemName: "questionmark.app")
                                .resizable()
                                .scaledToFit()
                        }
                    }
                }
                .frame(width: 64, height: 64)
                .dockItemShader()
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(launchFlashOpacity))
                }
                .modifier(ShineModifier(hoverStartDate: hoverAnimation == .shine ? hoverStartDate : nil))
                .scaleEffect(bobScale)
                .rotationEffect(.degrees(jiggleAngle))

                // Window indicator — lives outside all hover effects
                if windowCount > 0 || hasMinimizedWindows {
                    Capsule()
                        .fill(avgColor.opacity(windowCount > 0 ? 1.0 : 0.4))
                        .frame(width: windowCount > 0 ? 20 : 12, height: 4)
                        .offset(y: showLabels ? 8 : 6)
                }
            }
            .frame(width: 64, height: 64)
            .popover(isPresented: $showHoverLabel, attachmentAnchor: .rect(.rect(CGRect(x: 0, y: -12, width: 64, height: 64))), arrowEdge: .bottom) {
                Text(shortcut.label)
                    .font(.body)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .presentationCompactAdaptation(.none)
            }

            if showLabels {
                Text(shortcut.label)
                    .font(.caption2)
                    .lineLimit(1)
                    .frame(width: 64)
                    .truncationMode(.tail)
            }
        }
        .onTapGesture {
            guard !suppressNextTap else {
                suppressNextTap = false
                return
            }
            launchOrFocus()
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.4)
                .onEnded { _ in
                    suppressNextTap = true
                    withAnimation(.easeInOut(duration: 0.07)) { bobScale = 0.95 }
                    Task {
                        try? await Task.sleep(for: .milliseconds(75))
                        withAnimation(.easeInOut(duration: 0.07)) { bobScale = 1.05 }
                        try? await Task.sleep(for: .milliseconds(75))
                        withAnimation(.easeInOut(duration: 0.05)) { bobScale = 1.0 }
                    }
                    onDragStart(cachedIcon)
                }
        )
        .onHover { hovering in
            isHovering = hovering
            if hovering && !isReordering {
                if hoverAnimation == .shine { hoverStartDate = Date.now }
                startHoverAnimation()
                withAnimation(.easeInOut(duration: 0.12)) { showHoverLabel = hoverLabelEnabled }
            } else if !hovering && !isReordering {
                hoverStartDate = nil
                withAnimation(.easeOut(duration: 0.2)) {
                    bobScale = 1.0
                    jiggleAngle = 0
                }
                withAnimation(.easeInOut(duration: 0.12)) { showHoverLabel = false }
            }
        }
        .contextMenu {
            Button(Strings.Menu.edit) {
                NotificationCenter.default.post(name: .editShortcut, object: shortcut)
            }
            Button(Strings.Menu.remove, role: .destructive) { onRemove() }
        }
        .task(id: shortcut.iconFileName) {
            await loadIcon()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)) { notification in
            if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isFrontmost = app.bundleIdentifier == shortcut.bundleIdentifier
                }
            }
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didLaunchApplicationNotification)) { notification in
            if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
               app.bundleIdentifier == shortcut.bundleIdentifier {
                isLaunching = false
            }
        }
        .onAppear {
            isFrontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == shortcut.bundleIdentifier
        }
    }

    private func loadIcon() async {
        let url = AppShortcutStore.iconURL(for: shortcut.iconFileName)
        guard let result = await Task.detached(priority: .userInitiated, operation: { () -> (Image, Image, Color)? in
            guard let nsImage = NSImage(contentsOf: url) else { return nil }

            func render(into size: NSSize) -> NSImage {
                let img = NSImage(size: size)
                img.lockFocus()
                NSGraphicsContext.current?.imageInterpolation = .high
                nsImage.draw(in: NSRect(origin: .zero, size: size),
                             from: NSRect(origin: .zero, size: nsImage.size),
                             operation: .copy, fraction: 1.0)
                img.unlockFocus()
                return img
            }

            let icon     = Image(nsImage: render(into: NSSize(width: 48, height: 48)))
            let iconFull = Image(nsImage: render(into: NSSize(width: 64, height: 64)))
            let color    = ColorUtils.averageColor(of: nsImage) ?? .gray
            return (icon, iconFull, color)
        }).value else { return }

        cachedIcon     = result.0
        cachedIconFull = result.1
        avgColor       = result.2
    }

    private func startHoverAnimation() {
        switch hoverAnimation {
        case .bounce:
            animateBounce()
        case .pulse:
            animatePulse()
        case .jiggle:
            animateJiggle()
        case .pop:
            animatePop()
        case .shine:
            break  // driven entirely by ShineModifier / TimelineView
        case .none:
            break
        }
    }

    private func animateBounce() {
        let a = hoverSize.scale - 1.0
        let bounces: [(amplitude: Double, duration: Double)] = [
            (a,          0.08),
            (a * 0.65,   0.06),
            (a * 0.40,   0.05),
            (a * 0.25,   0.05),
            (a * 0.15,   0.04),
            (a * 0.08,   0.04),
            (a * 0.03,   0.03),
        ]

        Task {
            for (i, bounce) in bounces.enumerated() {
                guard isHovering else { break }
                let target = (i % 2 == 0) ? 1.0 + bounce.amplitude : 1.0 - bounce.amplitude * 0.5
                withAnimation(.easeInOut(duration: bounce.duration)) { bobScale = target }
                try? await Task.sleep(for: .milliseconds(Int(bounce.duration * 1000)))
            }
            guard isHovering else { return }
            withAnimation(.easeOut(duration: 0.04)) { bobScale = 1.0 }
        }
    }

    private func animatePulse() {
        Task {
            guard isHovering else { return }
            withAnimation(.easeInOut(duration: 0.2)) { bobScale = hoverSize.scale }
            try? await Task.sleep(for: .milliseconds(200))
            guard isHovering else { return }
            withAnimation(.easeInOut(duration: 0.2)) { bobScale = 1.0 }
        }
    }

    private func animateJiggle() {
        let steps: [(angle: Double, duration: Double)] = [
            ( 4,  0.05),
            (-4,  0.05),
            ( 3,  0.04),
            (-3,  0.04),
            ( 2,  0.04),
            (-2,  0.04),
            ( 1,  0.03),
            (-1,  0.03),
            ( 0,  0.03),
        ]

        Task {
            for step in steps {
                guard isHovering else { break }
                withAnimation(.easeInOut(duration: step.duration)) { jiggleAngle = step.angle }
                try? await Task.sleep(for: .milliseconds(Int(step.duration * 1000)))
            }
            guard isHovering else { return }
            withAnimation(.easeOut(duration: 0.03)) { jiggleAngle = 0 }
        }
    }

    private func animatePop() {
        bobScale = hoverSize.scale
        withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
            bobScale = 1.0
        }
    }

    private func startLaunchBounce() {
        guard isLaunching else { return }
        Task {
            while isLaunching {
                withAnimation(.easeIn(duration: 0.15)) { launchFlashOpacity = 0.5 }
                try? await Task.sleep(for: .milliseconds(150))
                withAnimation(.easeOut(duration: 0.3)) { launchFlashOpacity = 0 }
                try? await Task.sleep(for: .milliseconds(350))
            }
            withAnimation(.easeOut(duration: 0.2)) { launchFlashOpacity = 0 }
        }
    }


    private func launchOrFocus() {
        windowState.refresh()
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: shortcut.bundleIdentifier)

        // Finder is always running — open a new window instead of just activating
        if shortcut.bundleIdentifier == "com.apple.finder" {
            let path = NSString(string: finderDefaultDirectory).expandingTildeInPath
            NSWorkspace.shared.open(URL(filePath: path))
            return
        }

        if let app = runningApps.first {
            if app.isHidden { app.unhide() }

            if hasMinimizedWindows && windowCount == 0 {
                // All windows are minimized — openApplication restores them
                // the same way clicking an app in the macOS Dock does
                let config = NSWorkspace.OpenConfiguration()
                config.activates = true
                NSWorkspace.shared.openApplication(at: shortcut.appURL, configuration: config)
            } else {
                app.activate(options: .activateAllWindows)
            }
        } else {
            isLaunching = true
            startLaunchBounce()
            Task {
                try? await Task.sleep(for: .seconds(30))
                isLaunching = false
            }
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: shortcut.appURL, configuration: config)
        }

    }


}



// MARK: - Shine Modifier

/// Drives the shineGlint Metal shader continuously while hovering.
/// The TimelineView only runs while `hoverStartDate` is non-nil, so idle CPU cost is zero.
private struct ShineModifier: ViewModifier {
    let hoverStartDate: Date?

    func body(content: Content) -> some View {
        if let startDate = hoverStartDate {
            TimelineView(.animation) { ctx in
                let elapsed = ctx.date.timeIntervalSince(startDate)
                content
                    .layerEffect(
                        ShaderLibrary.shineGlint(
                            .float(Float(elapsed)),
                            .float(64),
                            .float(64)
                        ),
                        maxSampleOffset: .zero
                    )
            }
        } else {
            content
        }
    }
}
