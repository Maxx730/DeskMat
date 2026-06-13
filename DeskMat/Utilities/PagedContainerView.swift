import SwiftUI

struct PagedContainerView<PageContent: View>: View {
    let pageCount: Int
    var showChevrons: Bool = true
    var showDots: Bool = true
    var autoRotate: Bool = false
    var autoRotateInterval: Double = 3.0
    @ViewBuilder let content: (Int) -> PageContent

    @State private var currentPage = 0
    @State private var direction: Direction = .forward
    @State private var rotateEpoch = 0

    private enum Direction {
        case forward, backward
    }

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 0) {
                if showChevrons && pageCount > 1 {
                    chevron("chevron.left") { navigate(.backward) }
                } else {
                    Spacer().frame(width: 10)
                }

                ZStack {
                    ForEach(0..<pageCount, id: \.self) { index in
                        if index == currentPage {
                            content(index)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .transition(transition(for: direction))
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()

                if showChevrons && pageCount > 1 {
                    chevron("chevron.right") { navigate(.forward) }
                } else {
                    Spacer().frame(width: 20)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if showDots && pageCount > 1 {
                dots
            }
        }
        .task(id: autoRotate ? rotateEpoch : -1) {
            guard autoRotate && pageCount > 1 else { return }
            try? await Task.sleep(for: .seconds(autoRotateInterval))
            guard !Task.isCancelled else { return }
            navigate(.forward)
        }
    }

    private func navigate(_ dir: Direction) {
        direction = dir
        rotateEpoch += 1
        withAnimation(.easeInOut(duration: 0.25)) {
            switch dir {
            case .forward:  currentPage = (currentPage + 1) % pageCount
            case .backward: currentPage = (currentPage - 1 + pageCount) % pageCount
            }
        }
    }

    private func transition(for dir: Direction) -> AnyTransition {
        switch dir {
        case .forward:
            return .asymmetric(
                insertion: .move(edge: .trailing),
                removal:   .move(edge: .leading)
            )
        case .backward:
            return .asymmetric(
                insertion: .move(edge: .leading),
                removal:   .move(edge: .trailing)
            )
        }
    }

    private func chevron(_ name: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 20, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var dots: some View {
        HStack(spacing: 6) {
            ForEach(0..<pageCount, id: \.self) { index in
                Circle()
                    .frame(width: 4, height: 4)
                    .foregroundStyle(index == currentPage ? .white : .white.opacity(0.3))
                    .animation(.easeInOut(duration: 0.2), value: currentPage)
            }
        }
    }
}
