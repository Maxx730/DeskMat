import SwiftUI
import AppKit

struct ExpandableWidget<DockContent: View, PanelContent: View, PanelBackground: View>: View {
    let title: String
    var darkPanelTitle: Bool = false
    var showPanelTitle: Bool = true
    @ViewBuilder let dockContent: () -> DockContent
    @ViewBuilder let panelContent: () -> PanelContent
    @ViewBuilder let panelBackground: () -> PanelBackground

    @State private var isOpen = false
    @State private var detailPanel = WidgetDetailPanel()

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(isOpen ? 0.05 : 0))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(isOpen ? 0.1 : 0), lineWidth: 1)
                }

            dockContent()
                .opacity(isOpen ? 0 : 1)

            Image(systemName: "chevron.down.circle.fill")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .opacity(isOpen ? 1 : 0)
        }
        .animation(.easeInOut(duration: 0.15), value: isOpen)
        .onTapGesture { togglePanel() }
    }

    private func togglePanel() {
        if isOpen {
            detailPanel.dismiss()
            isOpen = false
            return
        }
        isOpen = true
        detailPanel.open {
            WidgetPanelChrome(title: title, onClose: {
                detailPanel.dismiss()
                isOpen = false
            }, darkTitle: darkPanelTitle, showTitle: showPanelTitle, background: panelBackground) {
                panelContent()
            }
        }
    }
}

extension ExpandableWidget where PanelBackground == MaterialPanelBackground {
    init(
        title: String,
        darkPanelTitle: Bool = false,
        showPanelTitle: Bool = true,
        @ViewBuilder dockContent: @escaping () -> DockContent,
        @ViewBuilder panelContent: @escaping () -> PanelContent
    ) {
        self.init(
            title: title,
            darkPanelTitle: darkPanelTitle,
            showPanelTitle: showPanelTitle,
            dockContent: dockContent,
            panelContent: panelContent,
            panelBackground: { MaterialPanelBackground() }
        )
    }
}
