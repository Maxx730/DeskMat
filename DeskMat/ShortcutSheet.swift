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
    @State private var customLabel: String = ""

    private var isEditing: Bool { shortcut != nil }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {

            // MARK: Header — icon + window title
            VStack(spacing: 10) {
                Button(action: pickIcon) {
                    ZStack(alignment: .bottomTrailing) {
                        Group {
                            if let image = selectedIconImage {
                                Image(nsImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 64, height: 64)
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                            } else {
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(.quaternary)
                                    .frame(width: 64, height: 64)
                                    .overlay {
                                        Image(systemName: "photo")
                                            .font(.system(size: 22))
                                            .foregroundStyle(.tertiary)
                                    }
                            }
                        }
                        Image(systemName: "pencil.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.white, .blue)
                            .offset(x: 5, y: 5)
                    }
                }
                .buttonStyle(.plain)
                .help(Strings.Shortcuts.chooseIcon)

                Text(isEditing ? Strings.Shortcuts.editAppShortcut : Strings.Shortcuts.addAppShortcut)
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 24)
            .padding(.bottom, 20)

            // MARK: Form rows
            VStack(spacing: 0) {
                formRow(label: Strings.Shortcuts.application) {
                    Text(selectedAppName.isEmpty ? Strings.Shortcuts.noAppSelected : selectedAppName)
                        .foregroundStyle(selectedAppName.isEmpty ? .tertiary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button(Strings.Shortcuts.chooseApp) { pickApp() }
                        .buttonStyle(.bordered)
                }

                formRow(label: Strings.Shortcuts.customLabel) {
                    TextField(selectedAppName.isEmpty ? "Label" : selectedAppName, text: $customLabel)
                        .textFieldStyle(.plain)
                        .foregroundStyle(customLabel.isEmpty ? .secondary : .primary)
                }
            }

            } // end inner wrapper

            .background(.background)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
            .padding(16)

            Divider()

            // MARK: Footer — error + actions
            VStack(spacing: 10) {
                if let error = errorMessage {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack {
                    Spacer()
                    Button(Strings.Common.cancel) { onDismiss() }
                        .buttonStyle(.bordered)
                    Button(isEditing ? Strings.Common.save : Strings.Shortcuts.add) { save() }
                        .disabled(isEditing ? selectedBundleID.isEmpty : (selectedAppURL == nil || selectedIconURL == nil))
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
        }
        .frame(width: 360)
        .onAppear {
            if let shortcut {
                selectedAppURL = shortcut.appURL
                selectedAppName = shortcut.displayName
                selectedBundleID = shortcut.bundleIdentifier
                customLabel = shortcut.customLabel ?? shortcut.displayName
                let iconURL = AppShortcutStore.iconURL(for: shortcut.iconFileName)
                selectedIconImage = NSImage(contentsOf: iconURL)
            }
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func formRow<RowContent: View>(label: String, @ViewBuilder content: () -> RowContent) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)
            content()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 11)
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
            if customLabel.isEmpty {
                customLabel = selectedAppName
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
                customLabel: customLabel.isEmpty ? nil : customLabel
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
                iconFileName = try AppShortcutStore.copyIcon(from: iconSourceURL, for: UUID())
            }

            var updated = shortcut
            updated.displayName = selectedAppName
            updated.bundleIdentifier = selectedBundleID
            updated.appURL = appURL
            updated.iconFileName = iconFileName
            updated.customLabel = customLabel.isEmpty ? nil : customLabel
            onSave(updated)
        } catch {
            errorMessage = Strings.Errors.failedToSaveIcon(error.localizedDescription)
        }
    }
}
