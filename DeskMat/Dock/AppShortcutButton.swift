import SwiftUI
import AppKit
import ApplicationServices


struct AppShortcutButton: View {
    let shortcut: AppShortcut
    let onRemove: () -> Void
    let isReordering: Bool
    let onDragStart: (Image?) -> Void
    var showWindowIndicator: Bool = true
    var onAfterTap: (() -> Void)? = nil

    @AppStorage("showLabels") private var showLabels = true
    @AppStorage("showIconBackground") private var showIconBackground = true
    @AppStorage("finderDefaultDirectory") private var finderDefaultDirectory = "~/"

    @Environment(WindowStateService.self) private var windowState

    @State private var isHovering = false
    @State private var avgColor: Color = .gray
    @State private var cachedIcon: Image?
    @State private var cachedIconFull: Image?
    @State private var isLoadingIcon: Bool = true
    @State private var isFrontmost = false

    private var windowCount: Int { windowState.info(for: shortcut.bundleIdentifier).count }
    private var hasMinimizedWindows: Bool { windowState.info(for: shortcut.bundleIdentifier).hasMinimized }

    @State private var suppressNextTap = false
    @State private var dragScale: Double = 1.0
    @State private var launchFlashOpacity: Double = 0
    @State private var isLaunching = false
    @State private var isRunning = false

    var body: some View {
        VStack(spacing: 10) {
            ZStack(alignment: .bottom) {
                // Icon + all hover effects (scale, rotation, shader, flash)
                ZStack {
                    if showIconBackground {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(avgColor)
                        if let icon = cachedIcon {
                            icon
                        } else if isLoadingIcon {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .controlSize(.small)
                        }
                        if isFrontmost {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(ColorUtils.brightenedHSV(avgColor), lineWidth: 2)
                                .padding(1)
                        }
                    } else {
                        if let icon = cachedIconFull {
                            icon
                        } else if isLoadingIcon {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .controlSize(.small)
                        }
                    }
                }
                .frame(width: 64, height: 64)
                .dockItemShader()
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(launchFlashOpacity))
                }
                .hoverAnimation(isReordering: isReordering, isHovering: $isHovering)
                .scaleEffect(dragScale)

                // Window indicator — lives outside all hover effects
                if showWindowIndicator && (windowCount > 0 || hasMinimizedWindows) {
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
            onAfterTap?()
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.4)
                .onEnded { _ in
                    suppressNextTap = true
                    withAnimation(.easeInOut(duration: 0.07)) { dragScale = 0.95 }
                    Task {
                        try? await Task.sleep(for: .milliseconds(75))
                        withAnimation(.easeInOut(duration: 0.07)) { dragScale = 1.05 }
                        try? await Task.sleep(for: .milliseconds(75))
                        withAnimation(.easeInOut(duration: 0.05)) { dragScale = 1.0 }
                    }
                    onDragStart(cachedIcon)
                }
        )
        .onHover { isHovering = $0 }
        .contextMenu {
            Button(Strings.Menu.edit) {
                NotificationCenter.default.post(name: .editShortcut, object: shortcut)
            }
            if isRunning {
                Divider()
                Button(Strings.Menu.closeAllWindows) {
                    closeAllWindows()
                }
            }
            Button(Strings.Menu.remove, role: .destructive) { onRemove() }
        }
        .task(id: shortcut.iconFileName) {
            await loadIcon()
        }
        .task(id: shortcut.backgroundColorHex) {
            if let hex = shortcut.backgroundColorHex {
                avgColor = ColorUtils.fromHex(hex)
            } else {
                await loadIcon()
            }
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
                isRunning = true
            }
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification)) { notification in
            if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
               app.bundleIdentifier == shortcut.bundleIdentifier {
                isRunning = false
            }
        }
        .onAppear {
            isFrontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == shortcut.bundleIdentifier
            isRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: shortcut.bundleIdentifier).isEmpty
        }
    }

    private func loadIcon() async {
        isLoadingIcon = true
        defer { isLoadingIcon = false }
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

        if let hex = shortcut.backgroundColorHex {
            avgColor = ColorUtils.fromHex(hex)
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


    private func closeAllWindows() {
        if !AXIsProcessTrusted() {
            let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            AXIsProcessTrustedWithOptions(opts as CFDictionary)
            return
        }

        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: shortcut.bundleIdentifier)
        guard let app = runningApps.first else { return }

        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement] else { return }

        for window in windows {
            var closeRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(window, kAXCloseButtonAttribute as CFString, &closeRef) == .success,
               let closeButton = closeRef {
                AXUIElementPerformAction(closeButton as! AXUIElement, kAXPressAction as CFString)
            }
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



