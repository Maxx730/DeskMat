import AppKit
import SwiftUI
import UniformTypeIdentifiers

private extension UTType {
    // Declared here since dskm is not registered in the project's Info.plist.
    // exportedAs always succeeds and lets open/save panels filter by extension.
    static let dskm = UTType(exportedAs: "com.deskmat.dskm")
}

extension AppDelegate {

    // MARK: - Window factory

    private func makeStandardWindow<V: View>(title: String, rootView: V) -> NSWindow {
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.setFrameSize(NSSize(width: 480, height: 0))
        hostingView.setFrameSize(NSSize(width: 480, height: hostingView.fittingSize.height))
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: hostingView.frame.size),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.contentView = hostingView
        window.center()
        window.isReleasedWhenClosed = false
        return window
    }

    // MARK: - Shortcuts

    @objc func addShortcut() {
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

        let window = makeStandardWindow(title: Strings.Windows.addShortcut, rootView: addView)
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        addShortcutWindow = window
    }

    @objc func editShortcut(_ notification: Notification) {
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

        let window = makeStandardWindow(title: Strings.Windows.editShortcut, rootView: editView)
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        editShortcutWindow = window
    }

    // MARK: - Export / Import

    @objc func exportDock() {
        let savePanel = NSSavePanel()
        savePanel.title = Strings.Windows.exportDock
        savePanel.allowedContentTypes = [.dskm]
        savePanel.nameFieldStringValue = Strings.Defaults.exportFileName
        savePanel.canCreateDirectories = true

        NSApp.activate(ignoringOtherApps: true)
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

    @objc func importDock() {
        let openPanel = NSOpenPanel()
        openPanel.title = Strings.Windows.importDock
        openPanel.allowedContentTypes = [.dskm]
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false

        NSApp.activate(ignoringOtherApps: true)
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

    // MARK: - Onboarding / Settings

    #if DEBUG
    @objc func showOnboardingDebug() {
        UserDefaults.standard.set(false, forKey: AppDelegate.onboardingCompletedKey)
        showOnboarding()
    }
    #endif

    func showOnboarding() {
        weak var windowRef: NSWindow?
        let view = OnboardingView(onComplete: {
            windowRef?.close()
        })
        let window = makeStandardWindow(title: Strings.Onboarding.windowTitle, rootView: view)
        windowRef = window
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow = window
    }

    @objc func openSettings() {
        if let window = settingsWindow {
            // Reuse the existing window — no need to re-inject the license manager.
            // LicenseManager is a reference type; @Observable propagates
            // updates through the same instance already held by the hosting view.
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView()
            .environment(entitlements)
        let window = makeStandardWindow(title: Strings.Windows.settings, rootView: settingsView)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = window
    }
}

extension AppDelegate: NSWindowDelegate {
    public func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window === onboardingWindow {
            UserDefaults.standard.set(true, forKey: AppDelegate.onboardingCompletedKey)
            onboardingWindow = nil
        } else if window === addShortcutWindow {
            addShortcutWindow = nil
        } else if window === editShortcutWindow {
            editShortcutWindow = nil
        }
    }
}
