import SwiftUI
import AppKit

struct FolderButton: View {
    let folder: AppFolder
    let isReordering: Bool
    let isOpen: Bool
    let onRemove: () -> Void
    let onEdit: () -> Void
    let onDragStart: (Image?) -> Void
    let onOpen: (AppFolder, CGRect) -> Void

    @AppStorage("showLabels") private var showLabels = true

    @State private var isHovering = false
    @State private var suppressNextTap = false
    @State private var dragScale: Double = 1.0
    @State private var customIcon: Image? = nil
    @State private var avgColor: Color = .gray
    @State private var buttonFrame: CGRect = .zero

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                // Background — always visible
                if let _ = customIcon {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(avgColor)
                } else {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(isOpen ? 0.25 : (isHovering ? 0.15 : 0.08)))
                        .stroke(Color.white.opacity(isOpen ? 0.3 : 0.12), lineWidth: 1)
                }

                // Content — triangle when open, icon/grid when closed
                if isOpen {
                    Image(systemName: "arrowshape.down.circle")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(.white)
                        .transition(.opacity.combined(with: .scale(scale: 0.6)))
                } else {
                    if let icon = customIcon {
                        icon
                            .resizable()
                            .scaledToFit()
                            .frame(width: 48, height: 48)
                            .transition(.opacity.combined(with: .scale(scale: 0.85)))
                    } else {
                        FolderMiniGrid(shortcuts: Array(folder.shortcuts.prefix(4)))
                            .padding(10)
                            .transition(.opacity.combined(with: .scale(scale: 0.85)))
                    }
                }
            }
            .animation(.easeInOut(duration: 0.18), value: isOpen)
            .frame(width: 64, height: 64)
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear { buttonFrame = geo.frame(in: .global) }
                        .onChange(of: geo.frame(in: .global)) { _, f in buttonFrame = f }
                }
            )
            .hoverAnimation(isReordering: isReordering, isHovering: $isHovering)
            .scaleEffect(dragScale)
            .onTapGesture {
                guard !suppressNextTap else { suppressNextTap = false; return }
                guard !isReordering else { return }
                onOpen(folder, buttonFrame)
            }
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.4)
                    .onEnded { _ in
                        suppressNextTap = true
                        withAnimation(.easeInOut(duration: 0.07)) { dragScale = 0.95 }
                        Task {
                            try? await Task.sleep(for: .milliseconds(75))
                            withAnimation(.easeInOut(duration: 0.07)) { dragScale = 1.05 }
                            try? await Task.sleep(for: .milliseconds(75))
                            withAnimation(.easeInOut(duration: 0.05)) { dragScale = 1.0 }
                        }
                        onDragStart(customIcon)
                    }
            )
            .onHover { isHovering = $0 }
            .contextMenu {
                Button("Edit Folder…") { onEdit() }
                Button("Remove Folder", role: .destructive) { onRemove() }
            }

            if showLabels {
                Text(folder.name)
                    .font(.caption2)
                    .lineLimit(1)
                    .frame(width: 64)
                    .truncationMode(.tail)
            }
        }
        .task(id: folder.iconFileName) {
            guard let fileName = folder.iconFileName else { customIcon = nil; avgColor = .gray; return }
            let url = AppShortcutStore.iconURL(for: fileName)
            let result = await Task.detached(priority: .userInitiated) { () -> (Image, Color)? in
                guard let ns = NSImage(contentsOf: url) else { return nil }
                let color = ColorUtils.averageColor(of: ns) ?? .gray
                return (Image(nsImage: ns), color)
            }.value
            customIcon = result?.0
            avgColor = result?.1 ?? .gray
        }
    }

}

// MARK: - Mini Icon Grid

private struct FolderMiniGrid: View {
    let shortcuts: [AppShortcut]

    private let columns = [GridItem(.flexible(), spacing: 4), GridItem(.flexible(), spacing: 4)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(0..<4, id: \.self) { index in
                if index < shortcuts.count {
                    MiniIconCell(iconFileName: shortcuts[index].iconFileName)
                } else {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white.opacity(0.12))
                        .aspectRatio(1, contentMode: .fit)
                }
            }
        }
    }
}

private struct MiniIconCell: View {
    let iconFileName: String
    @State private var icon: Image?

    var body: some View {
        Group {
            if let icon {
                icon
                    .resizable()
                    .scaledToFit()
            } else {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white.opacity(0.15))
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .task(id: iconFileName) {
            let url = AppShortcutStore.iconURL(for: iconFileName)
            icon = await Task.detached(priority: .userInitiated) {
                guard let ns = NSImage(contentsOf: url) else { return nil }
                return Image(nsImage: ns)
            }.value
        }
    }
}


