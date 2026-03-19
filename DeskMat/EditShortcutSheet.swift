import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct EditShortcutSheet: View {
    let shortcut: AppShortcut
    let onSave: (AppShortcut) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var selectedAppURL: URL?
    @State private var selectedAppName: String = ""
    @State private var selectedBundleID: String = ""
    @State private var selectedIconImage: NSImage?
    @State private var selectedIconURL: URL?
    @State private var iconChanged = false
    @State private var errorMessage: String?
    @State private var customLabel: String?

    var body: some View {
        VStack(spacing: 16) {
            Text("Edit App Shortcut")
                .font(.headline)

            TextField("Custom Label", text: Binding(
                get: { customLabel ?? "" },
                set: { customLabel = $0.isEmpty ? nil : $0 }
            ))
            .textFieldStyle(.roundedBorder)

            HStack {
                Text(selectedAppName.isEmpty ? "No app selected" : selectedAppName)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Choose App...") { pickApp() }
            }

            HStack {
                if let image = selectedIconImage {
                    Image(nsImage: image)
                        .resizable()
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 32))
                        .frame(width: 48, height: 48)
                }
                Button("Choose Icon...") { pickIcon() }
            }

            if let error = errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            HStack {
                Button("Cancel") { dismiss() }
                Button("Save") { saveShortcut() }
                    .disabled(selectedBundleID.isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 350)
        .onAppear {
            selectedAppURL = shortcut.appURL
            selectedAppName = shortcut.displayName
            selectedBundleID = shortcut.bundleIdentifier
            customLabel = shortcut.customLabel
            let iconURL = AppShortcutStore.iconURL(for: shortcut.iconFileName)
            selectedIconImage = NSImage(contentsOf: iconURL)
        }
    }

    private func pickApp() {
        let panel = NSOpenPanel()
        panel.title = "Select an Application"
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
        panel.title = "Select a Custom Icon Image"
        panel.allowedContentTypes = [UTType.image]
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            selectedIconURL = url
            selectedIconImage = NSImage(contentsOf: url)
            iconChanged = true
        }
    }

    private func saveShortcut() {
        guard let appURL = selectedAppURL,
              !selectedBundleID.isEmpty else {
            errorMessage = "Please select an app."
            return
        }

        do {
            var iconFileName = shortcut.iconFileName

            if iconChanged, let iconSourceURL = selectedIconURL {
                // Delete the old icon and copy the new one
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
            dismiss()
        } catch {
            errorMessage = "Failed to save icon: \(error.localizedDescription)"
        }
    }
}
