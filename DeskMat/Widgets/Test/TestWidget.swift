import SwiftUI

struct TestWidget: View {
    @AppStorage("showLabels") private var showLabels = true
    static let cellCount = 2

    private let pages: [(label: String, color: Color)] = [
        ("Page 1", .blue),
        ("Page 2", .purple),
        ("Page 3", .orange),
    ]

    var body: some View {
        VStack(spacing: 10) {
            DockWidget(cells: Self.cellCount) {
                PagedContainerView(pageCount: pages.count, showDots: false) { index in
                    let page = pages[index]
                    ZStack {
                        page.color.opacity(0.3)
                        Text(page.label)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white)
                            .textCase(.uppercase)
                    }
                }
            }
            if showLabels {
                Text("Test Widget")
                    .font(.caption2)
                    .lineLimit(1)
                    .frame(width: DockWidget<EmptyView>.width(for: Self.cellCount))
            }
        }
    }
}
