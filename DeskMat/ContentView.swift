import SwiftUI
import AppKit

struct ContentView: View {
    @State private var shortcuts: [AppShortcut] = AppShortcutStore.load()
    var body: some View {
        HStack {
            WeatherWidget()

            ForEach(shortcuts) { shortcut in
                AppShortcutButton(shortcut: shortcut, onRemove: {
                    removeShortcut(shortcut)
                }, onEdit: { updated in
                    updateShortcut(updated)
                })
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .contextMenu {
            Button("Add Shortcut...") {
                NotificationCenter.default.post(name: .addShortcut, object: nil)
            }
            Divider()
            Button("Export Dock...") {
                NotificationCenter.default.post(name: .exportDock, object: nil)
            }
            Button("Import Dock...") {
                NotificationCenter.default.post(name: .importDock, object: nil)
            }
            Divider()
            Button("Settings...") {
                NotificationCenter.default.post(name: .openSettings, object: nil)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .shortcutAdded)) { notification in
            if let newShortcut = notification.object as? AppShortcut {
                shortcuts.append(newShortcut)
                AppShortcutStore.save(shortcuts)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .dockImported)) { notification in
            if let imported = notification.object as? [AppShortcut] {
                shortcuts = imported
            }
        }
    }

    private func removeShortcut(_ shortcut: AppShortcut) {
        AppShortcutStore.deleteIcon(named: shortcut.iconFileName)
        shortcuts.removeAll { $0.id == shortcut.id }
        AppShortcutStore.save(shortcuts)
    }

    private func updateShortcut(_ updated: AppShortcut) {
        if let index = shortcuts.firstIndex(where: { $0.id == updated.id }) {
            shortcuts[index] = updated
            AppShortcutStore.save(shortcuts)
        }
    }
}

#Preview {
    ContentView()
}
