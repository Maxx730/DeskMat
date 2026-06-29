import SwiftUI

struct TasksWidget: View {
    static let cellCount = 2

    @State private var store = TasksStore()

    var body: some View {
        ExpandableWidget(title: Strings.Widgets.tasks, darkPanelTitle: true, showPanelTitle: false) {
            DockWidget(cells: Self.cellCount, backgroundColor: Color(red: 1.0, green: 0.96, blue: 0.70)) {
                ZStack {
                    NotePaperBackground()
                    dockFace
                }
            }
        } panelContent: {
            TasksDetailView(store: store)
        } panelBackground: {
            ZStack {
                Color(red: 1.0, green: 0.96, blue: 0.70)
                NotePaperBackground(lineSpacing: 22, marginX: 24, cornerRadius: 12)
            }
        }
    }

    @ViewBuilder
    private var dockFace: some View {
        let pending = store.tasks.filter { !$0.isDone }

        if pending.isEmpty {
            VStack(spacing: 2) {
                Image(systemName: "checklist")
                    .font(.system(size: 20))
                Text(Strings.Widgets.tasks)
                    .font(.caption2)
            }
            .foregroundStyle(.black.opacity(0.6))
        } else {
            PagedContainerView(
                pageCount: pending.count,
                showChevrons: false,
                showDots: false,
                autoRotate: pending.count > 1,
                autoRotateInterval: 4.0
            ) { index in
                VStack(alignment: .leading, spacing: 2) {
                    Text(pending[index].title)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.black.opacity(0.75))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    if !pending[index].description.isEmpty {
                        Text(pending[index].description)
                            .font(.caption2)
                            .foregroundStyle(.black.opacity(0.45))
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
            }
        }
    }
}
