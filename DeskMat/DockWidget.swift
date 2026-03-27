import SwiftUI

struct DockWidget<Content: View>: View {
    static var cellSize: CGFloat { 64 }

    let width: CGFloat
    let height: CGFloat
    let isLoading: Bool
    let onRefresh: (() async -> Void)?
    let content: Content
    @State private var isHovering = false

    init(
        cells: Int = 1,
        height: CGFloat = 64,
        isLoading: Bool = false,
        onRefresh: (() async -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.width = CGFloat(cells) * Self.cellSize
        self.height = height
        self.isLoading = isLoading
        self.onRefresh = onRefresh
        self.content = content()
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(red: 0.0, green: 0.0, blue: 0.0, opacity: isHovering ? 0.15 : 0.3))
                .stroke(Color(red: 0.0, green: 0.0, blue: 0.0, opacity: 0.5), lineWidth: 1)
            RoundedRectangle(cornerRadius: 10)
                .inset(by: 1)
                .fill(Color(red: 1.0, green: 1.0, blue: 1.0, opacity: 0.1))
                .stroke(Color(red: 1.0, green: 1.0, blue: 1.0, opacity: 0.1), lineWidth: 2)

            if isLoading {
                ProgressView()
                    .scaleEffect(0.7)
                    .tint(.white)
            } else {
                content
                    .dockItemShader()
            }
        }
        .frame(width: width, height: height)
        .onHover { isHovering = $0 }
        .animation(.easeInOut(duration: 0.15), value: isHovering)
        .overlay(alignment: .topTrailing) {
            if let onRefresh {
                Button {
                    Task { await onRefresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 8))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
                .padding(6)
            }
        }
    }
}
