import SwiftUI
import AppKit
import UserNotifications

@main
struct DeskMatApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Settings window is managed by AppDelegate
        Settings { EmptyView() }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    static let onboardingCompletedKey = "hasCompletedOnboarding"

    let entitlements = EntitlementManager()
    let systemMonitor = SystemMonitorService()
    var panel: DeskMatPanel!
    var statusItem: NSStatusItem!
    var settingsWindow: NSWindow?
    var addShortcutWindow: NSWindow?
    var editShortcutWindow: NSWindow?
    var onboardingWindow: NSWindow?
    var positionObserver: Any?
    var offsetObserver: Any?
    var appearanceObserver: Any?
    var globalHotkeyMonitor: Any?
    var localHotkeyMonitor: Any?
    var mouseGlobalMonitorToken: Any?
    var mouseLocalMonitorToken: Any?
    var hideWorkItem: DispatchWorkItem?
    var isDockHidden = false
    var isDockVisible = true

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        setupStatusItem()
        setupPanel()
        requestNotificationAuthorization()

        NotificationCenter.default.addObserver(self, selector: #selector(openSettings), name: .openSettings, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(exportDock), name: .exportDock, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(importDock), name: .importDock, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(addShortcut), name: .addShortcut, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(editShortcut(_:)), name: .editShortcut, object: nil)

        applyAppearance()

        if UserDefaults.standard.bool(forKey: "autoHideDock") {
            startAutoHide()
        }

        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification,
            object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            if UserDefaults.standard.bool(forKey: "autoHideDock") {
                self.startAutoHide()
            } else {
                self.stopAutoHide()
            }
        }

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in
            self?.evaluateMousePosition()
        }

        observeProStatus()

        if !UserDefaults.standard.bool(forKey: AppDelegate.onboardingCompletedKey) {
            showOnboarding()
        }

        appearanceObserver = UserDefaults.standard.observe(\.appearanceMode, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.applyAppearance() }
        }
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
        menu.item(withTitle: Strings.Menu.toggleDock)?.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(NSMenuItem(title: Strings.Menu.settings, action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: Strings.Menu.quitDeskMat, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    func requestNotificationAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
