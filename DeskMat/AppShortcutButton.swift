import SwiftUI
import AppKit

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
    case none = "None"
}

struct AppShortcutButton: View {
    let shortcut: AppShortcut
    let onRemove: () -> Void

    @AppStorage("showLabels") private var showLabels = true
    @AppStorage("hoverSize") private var hoverSize: HoverSize = .small
    @AppStorage("hoverAnimation") private var hoverAnimation: HoverAnimation = .bounce
    @AppStorage("finderDefaultDirectory") private var finderDefaultDirectory = "~/"
    
    @State private var isHovering = false
    @State private var bobScale: Double = 1.0
    @State private var avgColor: Color = .gray
    @State private var cachedIcon: Image?
    @State private var isFrontmost = false
    @State private var windowCount = 0
    @State private var jiggleAngle: Double = 0

    var body: some View {
        Button(action: { launchOrFocus() }) {
            VStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(avgColor)
                    (cachedIcon ?? Image(systemName: "questionmark.app"))
                    if isFrontmost {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(ColorUtils.lightened(avgColor), lineWidth: 2)
                            .padding(1)
                    }
                }
                .frame(width: 64, height: 64)
                .dockItemShader()
                .overlay(alignment: .bottom) {
                    if windowCount > 0 {
                        Capsule()
                            .fill(avgColor)
                            .frame(width: 20, height: 4)
                            .offset(y: showLabels ? 8 : 6)
                    }
                }
                .scaleEffect(bobScale)
                .rotationEffect(.degrees(jiggleAngle))
                .frame(width: 64, height: 64)

                if showLabels {
                    Text(shortcut.label)
                        .font(.caption2)
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
            if hovering {
                startHoverAnimation()
            } else {
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
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didLaunchApplicationNotification)) { _ in
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

    private func updateWindowCount() {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: shortcut.bundleIdentifier)
        guard let pid = apps.first?.processIdentifier else {
            windowCount = 0
            return
        }
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            windowCount = 0
            return
        }
        let count = windowList.filter {
            ($0[kCGWindowOwnerPID as String] as? pid_t) == pid
                && ($0[kCGWindowLayer as String] as? Int) == 0
        }.count
        windowCount = count
    }

    private func launchOrFocus() {
        // Finder is always running — open a new window instead of just activating
        if shortcut.bundleIdentifier == "com.apple.finder" {
            let path = NSString(string: finderDefaultDirectory).expandingTildeInPath
            NSWorkspace.shared.open(URL(filePath: path))
            return
        }

        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: shortcut.bundleIdentifier)

        if let app = runningApps.first {
            if app.isHidden {
                app.unhide()
            }

            NSApp.yieldActivation(to: app)
            app.activate(options: NSApplication.ActivationOptions.activateAllWindows)
        } else {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: shortcut.appURL, configuration: config)
        }
    }


}


