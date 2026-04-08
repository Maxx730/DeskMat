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
    var isFullscreenHidden = false
    var fullscreenTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        cleanSandboxTmp()
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
        startFullscreenObserver()

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
            let image = NSImage(named: "MenuBarIcon")
            image?.isTemplate = true
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

    /// Removes stale URLSession download temp files from the sandbox tmp directory.
    /// CFNetworkDownload_*.tmp files are left behind when a download is in-flight
    /// at the moment the app is killed. They are never needed after launch.
    private func cleanSandboxTmp() {
        let tmp = FileManager.default.temporaryDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: tmp, includingPropertiesForKeys: [.creationDateKey], options: .skipsHiddenFiles
        ) else { return }
        let cutoff = Date().addingTimeInterval(-60 * 60) // older than 1 hour
        for file in files where file.lastPathComponent.hasPrefix("CFNetworkDownload_") {
            let created = (try? file.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
            if created < cutoff {
                try? FileManager.default.removeItem(at: file)
            }
        }
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
