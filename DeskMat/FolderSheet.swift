import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct FolderSheet: View {
    let folder: AppFolder?
    let onSave: (AppFolder) -> Void
    let onDismiss: () -> Void

    @State private var name: String = ""
    @State private var shortcuts: [AppShortcut] = []
    @State private var customIconImage: NSImage? = nil
    @State private var customIconURL: URL? = nil
    @State private var iconChanged = false
    @State private var errorMessage: String? = nil

    private var hasCustomIcon: Bool { customIconImage != nil }

    private var isEditing: Bool { folder != nil }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {

                // Header: icon well + title
                VStack(spacing: 10) {
                    IconPickerButton(
                        image: customIconImage,
                        placeholderSystemImage: "folder.fill",
                        hasCustomIcon: hasCustomIcon,
                        onPick: pickIcon,
                        onReset: resetIcon
                    )
                    .help("Choose folder icon")

                    Text(isEditing ? "Edit Folder" : "New Folder")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 24)
                .padding(.bottom, 20)

                // Name field
                formRow(label: "Name") {
                    TextField("Folder name", text: $name)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background {
                            RoundedRectangle(cornerRadius: 7)
                                .fill(Color(NSColor.textBackgroundColor))
                            RoundedRectangle(cornerRadius: 7)
                                .stroke(.secondary.opacity(0.2), lineWidth: 1)
                        }
                }
            }
            .background(.background)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
            .padding(16)

            // Apps section
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Apps")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Add App…") { addApp() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                .padding(.horizontal, 16)

                if shortcuts.isEmpty {
                    Text("No apps added yet.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(shortcuts) { shortcut in
                                ShortcutRow(shortcut: shortcut) {
                                    shortcuts.removeAll { $0.id == shortcut.id }
                                }
                                if shortcut.id != shortcuts.last?.id {
                                    Divider().padding(.leading, 54)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 280)
                }
            }
            .padding(.bottom, 8)

            Spacer(minLength: 0)

            Divider()

            // Footer
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
                    Button(isEditing ? Strings.Common.save : "Create") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
        }
        .frame(width: 360)
        .frame(minHeight: 520)
        .onAppear {
            if let folder {
                name = folder.name
                shortcuts = folder.shortcuts
                if let fileName = folder.iconFileName {
                    let url = AppShortcutStore.iconURL(for: fileName)
                    customIconImage = NSImage(contentsOf: url)
                }
            }
        }
    }

    // MARK: - Shortcut Row

    private struct ShortcutRow: View {
        let shortcut: AppShortcut
        let onRemove: () -> Void
        @State private var icon: NSImage?

        var body: some View {
            HStack(spacing: 10) {
                Group {
                    if let icon {
                        Image(nsImage: icon)
                            .resizable()
                            .scaledToFit()
                    } else {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(.quaternary)
                    }
                }
                .frame(width: 28, height: 28)

                Text(shortcut.label)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button(action: onRemove) {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(.red)
                        .font(.system(size: 18))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .task(id: shortcut.iconFileName) {
                let url = AppShortcutStore.iconURL(for: shortcut.iconFileName)
                icon = await Task.detached(priority: .userInitiated) {
                    NSImage(contentsOf: url)
                }.value
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

    private func pickIcon() {
        let panel = NSOpenPanel()
        panel.title = "Select Folder Icon"
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            customIconURL = url
            customIconImage = NSImage(contentsOf: url)
            iconChanged = true
        }
    }

    private func resetIcon() {
        customIconURL = nil
        customIconImage = nil
        iconChanged = true
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.title = "Select Applications"
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }

        for url in panel.urls {
            guard let bundle = Bundle(url: url) else { continue }
            let displayName = bundle.infoDictionary?["CFBundleName"] as? String
                ?? bundle.infoDictionary?["CFBundleDisplayName"] as? String
                ?? url.deletingPathExtension().lastPathComponent
            let bundleID = bundle.bundleIdentifier ?? ""
            guard !shortcuts.contains(where: { $0.bundleIdentifier == bundleID }) else { continue }
            let appIcon = NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false))
            guard let iconFileName = try? AppShortcutStore.copyIcon(from: appIcon, for: UUID()) else { continue }
            shortcuts.append(AppShortcut(
                displayName: displayName,
                bundleIdentifier: bundleID,
                appURL: url,
                iconFileName: iconFileName
            ))
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else {
            errorMessage = "Please enter a folder name."
            return
        }

        do {
            var iconFileName: String? = folder?.iconFileName

            if iconChanged {
                if let old = folder?.iconFileName {
                    AppShortcutStore.deleteIcon(named: old)
                }
                if let url = customIconURL {
                    iconFileName = try AppShortcutStore.copyIcon(from: url, for: UUID())
                } else {
                    iconFileName = nil
                }
            }

            // Clean up icon files for shortcuts removed during editing
            if let original = folder {
                let removed = original.shortcuts.filter { orig in
                    !shortcuts.contains(where: { $0.id == orig.id })
                }
                for s in removed { AppShortcutStore.deleteIcon(named: s.iconFileName) }
            }

            if isEditing, var updated = folder {
                updated.name = trimmedName
                updated.shortcuts = shortcuts
                updated.iconFileName = iconFileName
                onSave(updated)
            } else {
                onSave(AppFolder(name: trimmedName, shortcuts: shortcuts, iconFileName: iconFileName))
            }
        } catch {
            errorMessage = "Failed to save icon: \(error.localizedDescription)"
        }
    }
}
