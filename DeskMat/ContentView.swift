import SwiftUI
import AppKit

struct ContentView: View {
    @State private var shortcuts: [AppShortcut] = AppShortcutStore.load()
    @AppStorage("showWeatherWidget") private var showWeatherWidget = true
    @AppStorage("showClockWidget") private var showClockWidget = true
    @AppStorage("showImageWidget") private var showImageWidget = true
    @AppStorage("showDockBackground") private var showDockBackground = true
    @AppStorage("dockBackgroundColorHex") private var dockBackgroundColorHex: String = "#000000ff"

    var body: some View {
        ZStack {
            HStack {
                if showWeatherWidget {
                    WeatherWidget()
                }

                ForEach(shortcuts) { shortcut in
                    AppShortcutButton(shortcut: shortcut, onRemove: {
                        removeShortcut(shortcut)
                    })
                }

                if showImageWidget {
                    ImageWidget()
                }

                if showClockWidget {
                    ClockWidget()
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .contextMenu {
                Button(Strings.Menu.addShortcut) {
                    NotificationCenter.default.post(name: .addShortcut, object: nil)
                }
                Divider()
                Button(Strings.Menu.exportDock) {
                    NotificationCenter.default.post(name: .exportDock, object: nil)
                }
                Button(Strings.Menu.importDock) {
                    NotificationCenter.default.post(name: .importDock, object: nil)
                }
                Divider()
                Button(Strings.Menu.settings) {
                    NotificationCenter.default.post(name: .openSettings, object: nil)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .shortcutAdded)) { notification in
                if let newShortcut = notification.object as? AppShortcut {
                    shortcuts.append(newShortcut)
                    AppShortcutStore.save(shortcuts)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .shortcutEdited)) { notification in
                if let updated = notification.object as? AppShortcut {
                    updateShortcut(updated)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .dockImported)) { notification in
                if let imported = notification.object as? [AppShortcut] {
                    shortcuts = imported
                }
            }
            
        }
        .background {
            if showDockBackground {
                VisualEffectBackground()
            } else {
                RoundedRectangle(cornerRadius: 16)
                    .fill(ColorUtils.fromHex(dockBackgroundColorHex))
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
            // we need to 'refresh' the icons in the dock here
        }
    }
}

#Preview {
    ContentView()
}
