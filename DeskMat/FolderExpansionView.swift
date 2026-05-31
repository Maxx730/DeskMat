import SwiftUI
import AppKit

struct FolderExpansionView: View {
    let folder: AppFolder
    let onLaunch: () -> Void
    let windowState: WindowStateService
    let entitlements: LicenseManager

    let dockBackground: DockBackground
    let dockBackgroundColorHex: String
    let dockCornerRadius: Double

    var body: some View {
        VStack(spacing: 8) {
            ForEach(folder.shortcuts) { shortcut in
                AppShortcutButton(
                    shortcut: shortcut,
                    onRemove: {},
                    isReordering: false,
                    onDragStart: { _ in },
                    showWindowIndicator: false,
                    onAfterTap: onLaunch
                )
            }
        }
        .environment(windowState)
        .environment(entitlements)
        .padding(8)
        .background {
            if dockBackground == .color {
                RoundedRectangle(cornerRadius: dockCornerRadius)
                    .fill(ColorUtils.fromHex(dockBackgroundColorHex))
            } else if dockBackground == .transparent {
                Color.clear
            } else {
                RoundedRectangle(cornerRadius: dockCornerRadius)
                    .fill(.ultraThinMaterial)
            }
        }
    }
}

#Preview {
    FolderExpansionView(
        folder: AppFolder(name: "Dev Tools", shortcuts: []),
        onLaunch: {},
        windowState: WindowStateService(),
        entitlements: LicenseManager(),
        dockBackground: .system,
        dockBackgroundColorHex: "#000000ff",
        dockCornerRadius: 16
    )
    .padding()
    .background(.black)
}
