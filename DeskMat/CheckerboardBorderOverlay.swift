import SwiftUI

struct CheckerboardBorderOverlay: View {
    let dockSize: CGSize
    let cornerSize: CGFloat = 18.0
    let startDate = Date.now

    var body: some View {
        TimelineView(.animation) { context in
            let elapsed = context.date.timeIntervalSince(startDate)

            RoundedRectangle(cornerRadius: cornerSize)
                .stroke(.white, lineWidth: 1)
                .colorEffect(
                    ShaderLibrary.checkerboard(
                        .float(Float(elapsed)),
                        .float(Float(6))
                    )
                )
                .allowsHitTesting(false)
        }
    }
}
