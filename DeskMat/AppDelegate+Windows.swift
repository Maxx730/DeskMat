import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension AppDelegate {
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

    @objc func exportDock() {
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

    @objc func importDock() {
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

    func showOnboarding() {
        let view = OnboardingView(onComplete: { [weak self] in
            self?.onboardingWindow?.close()
        })
        let hostingView = NSHostingView(rootView: view)
        hostingView.setFrameSize(NSSize(width: 480, height: 0))
        let size = NSSize(width: 480, height: hostingView.fittingSize.height)
        hostingView.setFrameSize(size)

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = Strings.Onboarding.windowTitle
        window.contentView = hostingView
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        onboardingWindow = window
    }

    @objc func openSettings() {
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView()
        let hostingView = NSHostingView(rootView: settingsView)
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

extension AppDelegate: NSWindowDelegate {
    public func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window === onboardingWindow else { return }
        UserDefaults.standard.set(true, forKey: AppDelegate.onboardingCompletedKey)
        onboardingWindow = nil
    }
}
