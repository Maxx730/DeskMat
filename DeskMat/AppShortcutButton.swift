import SwiftUI
import AppKit
import ApplicationServices

enum HoverSize: String, CaseIterable {
    case small = "Small"
    case medium = "Medium"
    case large = "Large"

    var scale: Double {
        switch self {
        case .small: 1.2
        case .medium: 1.5
        case .large: 1.8
        }
    }
}

enum HoverAnimation: String, CaseIterable {
    case bounce = "Bounce"
    case pulse = "Pulse"
    case jiggle = "Jiggle"
    case pop = "Pop"
    case shine = "Shine"
    case none = "None"
}

struct AppShortcutButton: View {
    let shortcut: AppShortcut
    let onRemove: () -> Void
    let isReordering: Bool
    let onDragStart: (Image?) -> Void

    @AppStorage("showLabels") private var showLabels = true
    @AppStorage("hoverSize") private var hoverSize: HoverSize = .small
    @AppStorage("hoverAnimation") private var hoverAnimation: HoverAnimation = .bounce
    @AppStorage("finderDefaultDirectory") private var finderDefaultDirectory = "~/"
    @AppStorage("advancedWindowManagement") private var advancedWindowManagement = false
    
    @State private var isHovering = false
    @State private var bobScale: Double = 1.0
    @State private var avgColor: Color = .gray
    @State private var cachedIcon: Image?
    @State private var isFrontmost = false
    @State private var windowCount = 0
    @State private var hasMinimizedWindows = false
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
                    RoundedRectangle(cornerRadius: 10)
                        .fill(avgColor)
                    (cachedIcon ?? Image(systemName: "questionmark.app"))
                    if isFrontmost {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(ColorUtils.brightenedHSV(avgColor), lineWidth: 2)
                            .padding(1)
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
            } else if !hovering && !isReordering {
                hoverStartDate = nil
                withAnimation(.easeOut(duration: 0.2)) {
                    bobScale = 1.0
                    jiggleAngle = 0
                }
            }
        }
        .contextMenu {
            Button(Strings.Menu.edit) {
                NotificationCenter.default.post(name: .editShortcut, object: shortcut)
            }
            Button(Strings.Menu.remove, role: .destructive) { onRemove() }
        }
        .task(id: shortcut.iconFileName) {
            loadIcon()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)) { notification in
            if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isFrontmost = app.bundleIdentifier == shortcut.bundleIdentifier
                }
            }
            updateWindowCount()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didDeactivateApplicationNotification)) { _ in
            updateWindowCount()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didLaunchApplicationNotification)) { notification in
            if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
               app.bundleIdentifier == shortcut.bundleIdentifier {
                isLaunching = false
            }
            updateWindowCount()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification)) { _ in
            updateWindowCount()
        }
        .onAppear {
            isFrontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == shortcut.bundleIdentifier
            updateWindowCount()
        }
    }

    private func loadIcon() {
        let url = AppShortcutStore.iconURL(for: shortcut.iconFileName)
        guard let nsImage = NSImage(contentsOf: url) else { return }

        // Pre-render at exact pixel size for crisp display
        let targetSize = NSSize(width: 48, height: 48)
        let sharpImage = NSImage(size: targetSize)
        sharpImage.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        nsImage.draw(in: NSRect(origin: .zero, size: targetSize),
                     from: NSRect(origin: .zero, size: nsImage.size),
                     operation: .copy, fraction: 1.0)
        sharpImage.unlockFocus()

        cachedIcon = Image(nsImage: sharpImage)

        if let color = ColorUtils.averageColor(of: nsImage) {
            avgColor = color
        }
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

    private func unminimizeWindows(for app: NSRunningApplication) {
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement] else { return }
        for window in windows {
            // Set minimized=false unconditionally — no-op on visible windows,
            // restores minimized ones. Avoids the CFBoolean bridging cast.
            AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }
    }

    private func updateWindowCount(runningApps: [NSRunningApplication]? = nil) {
        let apps = runningApps ?? NSRunningApplication.runningApplications(withBundleIdentifier: shortcut.bundleIdentifier)
        guard let pid = apps.first?.processIdentifier else {
            windowCount = 0
            hasMinimizedWindows = false
            return
        }
        guard let allWindows = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            windowCount = 0
            hasMinimizedWindows = false
            return
        }
        let appWindows = allWindows.filter {
            ($0[kCGWindowOwnerPID as String] as? pid_t) == pid
                && ($0[kCGWindowLayer as String] as? Int) == 0
        }
        let onScreenCount = appWindows.filter {
            ($0[kCGWindowIsOnscreen as String] as? Bool) == true
        }.count
        windowCount = onScreenCount
        hasMinimizedWindows = appWindows.count > onScreenCount
    }

    private func launchOrFocus() {
        // Refresh window state synchronously before branching. Workspace notifications
        // will also fire after activation and call updateWindowCount() again — that's
        // expected and keeps the dot indicator up to date.
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: shortcut.bundleIdentifier)
        updateWindowCount(runningApps: runningApps)

        // Finder is always running — open a new window instead of just activating
        if shortcut.bundleIdentifier == "com.apple.finder" {
            let path = NSString(string: finderDefaultDirectory).expandingTildeInPath
            NSWorkspace.shared.open(URL(filePath: path))
            return
        }

        if let app = runningApps.first {
            if app.isHidden { app.unhide() }

            if advancedWindowManagement && AXIsProcessTrusted() {
                // Guaranteed unminimize via Accessibility API
                unminimizeWindows(for: app)
                app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
            } else if hasMinimizedWindows && windowCount == 0 {
                // All windows are minimized — openApplication restores them
                // the same way clicking an app in the macOS Dock does
                let config = NSWorkspace.OpenConfiguration()
                config.activates = true
                NSWorkspace.shared.openApplication(at: shortcut.appURL, configuration: config)
            } else {
                app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
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

        // Refresh indicator after the window animation completes.
        Task {
            try? await Task.sleep(for: .milliseconds(650))
            updateWindowCount()
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
