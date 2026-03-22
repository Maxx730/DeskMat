import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ShortcutSheet: View {
    let shortcut: AppShortcut?
    let onSave: (AppShortcut) -> Void
    let onDismiss: () -> Void

    @State private var selectedAppURL: URL?
    @State private var selectedAppName: String = ""
    @State private var selectedBundleID: String = ""
    @State private var selectedIconImage: NSImage?
    @State private var selectedIconURL: URL?
    @State private var iconChanged = false
    @State private var errorMessage: String?
    @State private var customLabel: String?

    private var isEditing: Bool { shortcut != nil }

    var body: some View {
        VStack {
            SettingsSection(title: Strings.Shortcuts.application) {
                VStack {
                    HStack {
                        Text(selectedAppName.isEmpty ? Strings.Shortcuts.noAppSelected : selectedAppName)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button(Strings.Shortcuts.chooseApp) { pickApp() }
                    }
                }
            }
            SettingsSection(title: Strings.Shortcuts.icon) {
                HStack {
                    if let image = selectedIconImage {
                        Image(nsImage: image)
                            .resizable()
                            .frame(width: 32, height: 32)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    } else {
                        Image(systemName: "photo")
                            .font(.system(size: 16))
                            .frame(width: 32, height: 32)
                    }
                    Spacer()
                    Button(Strings.Shortcuts.chooseIcon) { pickIcon() }
                }
            }
            SettingsSection {
                Button(Strings.Shortcuts.chooseIcon) { pickIcon() }
            }

            if let error = errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            HStack {
                Button(Strings.Common.cancel) { onDismiss() }
                Button(isEditing ? Strings.Common.save : Strings.Shortcuts.add) { save() }
                    .disabled(isEditing ? selectedBundleID.isEmpty : (selectedAppURL == nil || selectedIconURL == nil))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 350)
        .onAppear {
            if let shortcut {
                selectedAppURL = shortcut.appURL
                selectedAppName = shortcut.displayName
                selectedBundleID = shortcut.bundleIdentifier
                customLabel = shortcut.customLabel
                let iconURL = AppShortcutStore.iconURL(for: shortcut.iconFileName)
                selectedIconImage = NSImage(contentsOf: iconURL)
            }
        }
    }

    private func pickApp() {
        let panel = NSOpenPanel()
        panel.title = Strings.Shortcuts.selectAnApplication
        panel.allowedContentTypes = [UTType.application]
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            selectedAppURL = url
            if let bundle = Bundle(url: url) {
                selectedAppName = bundle.infoDictionary?["CFBundleName"] as? String
                    ?? bundle.infoDictionary?["CFBundleDisplayName"] as? String
                    ?? url.deletingPathExtension().lastPathComponent
                selectedBundleID = bundle.bundleIdentifier ?? ""
            } else {
                selectedAppName = url.deletingPathExtension().lastPathComponent
                selectedBundleID = ""
            }
        }
    }

    private func pickIcon() {
        let panel = NSOpenPanel()
        panel.title = Strings.Shortcuts.selectACustomIconImage
        panel.allowedContentTypes = [UTType.image]
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            selectedIconURL = url
            selectedIconImage = NSImage(contentsOf: url)
            iconChanged = true
        }
    }

    private func save() {
        if isEditing {
            saveExisting()
        } else {
            saveNew()
        }
    }

    private func saveNew() {
        guard let appURL = selectedAppURL,
              let iconSourceURL = selectedIconURL,
              !selectedBundleID.isEmpty else {
            errorMessage = Strings.Errors.selectBothAppAndIcon
            return
        }

        let shortcutID = UUID()
        do {
            let iconFileName = try AppShortcutStore.copyIcon(from: iconSourceURL, for: shortcutID)
            let newShortcut = AppShortcut(
                displayName: selectedAppName,
                bundleIdentifier: selectedBundleID,
                appURL: appURL,
                iconFileName: iconFileName,
                customLabel: customLabel
            )
            onSave(newShortcut)
        } catch {
            errorMessage = Strings.Errors.failedToSaveIcon(error.localizedDescription)
        }
    }

    private func saveExisting() {
        guard let shortcut,
              let appURL = selectedAppURL,
              !selectedBundleID.isEmpty else {
            errorMessage = Strings.Errors.selectAnApp
            return
        }

        do {
            var iconFileName = shortcut.iconFileName

            if iconChanged, let iconSourceURL = selectedIconURL {
                AppShortcutStore.deleteIcon(named: shortcut.iconFileName)
                iconFileName = try AppShortcutStore.copyIcon(from: iconSourceURL, for: shortcut.id)
            }

            var updated = shortcut
            updated.displayName = selectedAppName
            updated.bundleIdentifier = selectedBundleID
            updated.appURL = appURL
            updated.iconFileName = iconFileName
            updated.customLabel = customLabel
            onSave(updated)
        } catch {
            errorMessage = Strings.Errors.failedToSaveIcon(error.localizedDescription)
        }
    }
}
