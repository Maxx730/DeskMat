import SwiftUI
import AppKit
import UniformTypeIdentifiers
import UserNotifications

enum DockPosition: String, CaseIterable {
    case bottom = "Bottom"
    case top = "Top"
}

@main
struct DeskMatApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Settings window is managed by AppDelegate
        Settings { EmptyView() }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var panel: DeskMatPanel!
    var statusItem: NSStatusItem!
    var settingsWindow: NSWindow?
    var addShortcutWindow: NSWindow?
    var editShortcutWindow: NSWindow?
    private var positionObserver: Any?
    private var offsetObserver: Any?
    private var globalHotkeyMonitor: Any?
    private var localHotkeyMonitor: Any?
    private var isDockHidden = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide from dock, keep menu bar
        NSApp.setActivationPolicy(.accessory)

        setupStatusItem()
        setupPanel()
        requestNotificationAuthorization()

        NotificationCenter.default.addObserver(self, selector: #selector(openSettings), name: .openSettings, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(exportDock), name: .exportDock, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(importDock), name: .importDock, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(addShortcut), name: .addShortcut, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(editShortcut(_:)), name: .editShortcut, object: nil)

        setupHotkey()
    }

    private func requestNotificationAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            let size: CGFloat = 18
            let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
                NSColor.white.setFill()
                let path = NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 6, yRadius: 6)
                path.fill()
                return true
            }
            image.isTemplate = true
            button.image = image
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: Strings.Menu.addShortcut, action: #selector(addShortcut), keyEquivalent: "a"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: Strings.Menu.exportDock, action: #selector(exportDock), keyEquivalent: "e"))
        menu.addItem(NSMenuItem(title: Strings.Menu.importDock, action: #selector(importDock), keyEquivalent: "i"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: Strings.Menu.toggleDock, action: #selector(toggleDock), keyEquivalent: "d"))
        menu.item(withTitle: Strings.Menu.toggleDock)?.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(NSMenuItem(title: Strings.Menu.settings, action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: Strings.Menu.quitDeskMat, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    private func setupPanel() {
        let content = ContentView()
            .background(VisualEffectBackground())

        let hostingView = NSHostingView(rootView: content)
        hostingView.setFrameSize(hostingView.fittingSize)

        panel = DeskMatPanel(
            contentRect: NSRect(x: 0, y: 0, width: hostingView.fittingSize.width, height: hostingView.fittingSize.height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.contentView = hostingView
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = false
        panel.isMovable = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.acceptsMouseMovedEvents = true

        // Resize panel when SwiftUI content changes size
        hostingView.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(hostingViewFrameChanged(_:)), name: NSView.frameDidChangeNotification, object: hostingView)

        repositionPanel()
        panel.orderFrontRegardless()

        // Reposition when the setting changes
        positionObserver = UserDefaults.standard.observe(\.dockPosition, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.repositionPanel()
            }
        }
        offsetObserver = UserDefaults.standard.observe(\.dockOffset, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.repositionPanel()
            }
        }
    }

    @objc private func hostingViewFrameChanged(_ notification: Notification) {
        guard let hostingView = notification.object as? NSView else { return }
        let newSize = hostingView.fittingSize
        panel.setContentSize(newSize)
        repositionPanel()
    }

    private func repositionPanel() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let panelSize = panel.frame.size
        let x = screenFrame.midX - panelSize.width / 2
        let position = DockPosition(rawValue: UserDefaults.standard.string(forKey: "dockPosition") ?? "Bottom") ?? .bottom
        let offset = CGFloat(UserDefaults.standard.integer(forKey: "dockOffset"))
        let y: CGFloat
        switch position {
        case .bottom:
            y = screenFrame.minY + offset
        case .top:
            y = screenFrame.maxY - panelSize.height - offset
        }
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    @objc private func addShortcut() {
        if let window = addShortcutWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let addView = ShortcutSheet(shortcut: nil, onSave: { [weak self] newShortcut in
            NotificationCenter.default.post(name: .shortcutAdded, object: newShortcut)
            self?.addShortcutWindow?.close()
            self?.addShortcutWindow = nil
        }, onDismiss: { [weak self] in
            self?.addShortcutWindow?.close()
            self?.addShortcutWindow = nil
        })
        let hostingView = NSHostingView(rootView: addView)
        hostingView.setFrameSize(NSSize(width: 480, height: 0))
        let size = NSSize(width: 480, height: hostingView.fittingSize.height)
        hostingView.setFrameSize(size)

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = Strings.Windows.addShortcut
        window.contentView = hostingView
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        addShortcutWindow = window
    }

    @objc private func editShortcut(_ notification: Notification) {
        guard let shortcut = notification.object as? AppShortcut else { return }

        if let window = editShortcutWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let editView = ShortcutSheet(shortcut: shortcut, onSave: { [weak self] updated in
            NotificationCenter.default.post(name: .shortcutEdited, object: updated)
            self?.editShortcutWindow?.close()
            self?.editShortcutWindow = nil
        }, onDismiss: { [weak self] in
            self?.editShortcutWindow?.close()
            self?.editShortcutWindow = nil
        })
        let hostingView = NSHostingView(rootView: editView)
        hostingView.setFrameSize(NSSize(width: 480, height: 0))
        let size = NSSize(width: 480, height: hostingView.fittingSize.height)
        hostingView.setFrameSize(size)

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = Strings.Windows.editShortcut
        window.contentView = hostingView
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        editShortcutWindow = window
    }

    @objc private func exportDock() {
        guard let dskmType = UTType(filenameExtension: "dskm") else { return }
        let savePanel = NSSavePanel()
        savePanel.title = Strings.Windows.exportDock
        savePanel.allowedContentTypes = [dskmType]
        savePanel.nameFieldStringValue = Strings.Defaults.exportFileName
        savePanel.canCreateDirectories = true

        savePanel.begin { [weak self] response in
            guard response == .OK, let url = savePanel.url else { return }
            do {
                try AppShortcutStore.exportDock(to: url)
                self?.sendNotification(title: Strings.Notifications.dockExported, body: Strings.Notifications.dockExportedBody(url.lastPathComponent))
            } catch {
                self?.sendNotification(title: Strings.Notifications.exportFailed, body: error.localizedDescription)
            }
        }
    }

    @objc private func importDock() {
        guard let dskmType = UTType(filenameExtension: "dskm") else { return }
        let openPanel = NSOpenPanel()
        openPanel.title = Strings.Windows.importDock
        openPanel.allowedContentTypes = [dskmType]
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false

        openPanel.begin { [weak self] response in
            guard response == .OK, let url = openPanel.url else { return }
            do {
                let shortcuts = try AppShortcutStore.importDock(from: url)
                NotificationCenter.default.post(name: .dockImported, object: shortcuts)
                self?.sendNotification(title: Strings.Notifications.dockImported, body: Strings.Notifications.dockImportedBody(count: shortcuts.count, fileName: url.lastPathComponent))
            } catch {
                self?.sendNotification(title: Strings.Notifications.importFailed, body: error.localizedDescription)
            }
        }
    }

    private func setupHotkey() {
        // Cmd+Shift+D to toggle dock visibility
        let mask: NSEvent.ModifierFlags = [.command, .shift]
        let keyCode: UInt16 = 2 // 'd' key

        globalHotkeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == mask && event.keyCode == keyCode {
                self?.toggleDock()
            }
        }
        localHotkeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == mask && event.keyCode == keyCode {
                self?.toggleDock()
                return nil
            }
            return event
        }
    }

    @objc private func toggleDock() {
        isDockHidden.toggle()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            panel.animator().alphaValue = isDockHidden ? 0 : 1
        }
    }

    @objc private func openSettings() {
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView()
        let hostingView = NSHostingView(rootView: settingsView)
        // Set width first so fittingSize computes the correct height for this width
        hostingView.setFrameSize(NSSize(width: 480, height: 0))
        let settingsSize = NSSize(width: 480, height: hostingView.fittingSize.height)
        hostingView.setFrameSize(settingsSize)

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: settingsSize),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = Strings.Windows.settings
        window.contentView = hostingView
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        settingsWindow = window
    }
}

extension UserDefaults {
    @objc dynamic var dockPosition: String {
        return string(forKey: "dockPosition") ?? "Bottom"
    }
    @objc dynamic var dockOffset: Int {
        return integer(forKey: "dockOffset")
    }
}

extension Notification.Name {
    static let addShortcut = Notification.Name("addShortcut")
    static let openSettings = Notification.Name("openSettings")
    static let exportDock = Notification.Name("exportDock")
    static let importDock = Notification.Name("importDock")
    static let dockImported = Notification.Name("dockImported")
    static let shortcutAdded = Notification.Name("shortcutAdded")
    static let editShortcut = Notification.Name("editShortcut")
    static let shortcutEdited = Notification.Name("shortcutEdited")
}


class DeskMatPanel: NSPanel {
    override var canBecomeKey: Bool { true }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        NSApp.activate(ignoringOtherApps: true)
        makeKey()
    }
}

struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = 16
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
