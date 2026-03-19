import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct AddShortcutSheet: View {
    let onAdd: (AppShortcut) -> Void

    @State private var selectedAppURL: URL?
    @State private var selectedAppName: String = ""
    @State private var selectedBundleID: String = ""
    @State private var selectedIconImage: NSImage?
    @State private var selectedIconURL: URL?
    @State private var errorMessage: String?
    @State private var customLabel: String?

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                Rectangle().fill(.black).frame(width: 64, height: 64).clipShape(RoundedRectangle(cornerRadius: 10)).opacity(0.5)
                VStack {
                    TextField("Custom Label", text: Binding(
                        get: { customLabel ?? "" },
                        set: { customLabel = $0.isEmpty ? nil : $0 }
                    ))
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                    Button("Choose App...") { pickApp() }
                }
            }

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
                Button("Cancel") { NSApp.keyWindow?.close() }
                Button("Add") { addShortcut() }
                    .disabled(selectedAppURL == nil || selectedIconURL == nil)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 350)
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
        }
    }

    private func addShortcut() {
        guard let appURL = selectedAppURL,
              let iconSourceURL = selectedIconURL,
              !selectedBundleID.isEmpty else {
            errorMessage = "Please select both an app and an icon image."
            return
        }

        let shortcutID = UUID()
        do {
            let iconFileName = try AppShortcutStore.copyIcon(from: iconSourceURL, for: shortcutID)
            let shortcut = AppShortcut(
                displayName: selectedAppName,
                bundleIdentifier: selectedBundleID,
                appURL: appURL,
                iconFileName: iconFileName,
                customLabel: customLabel
            )
            onAdd(shortcut)
        } catch {
            errorMessage = "Failed to save icon: \(error.localizedDescription)"
        }
    }
}
