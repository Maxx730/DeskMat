import SwiftUI

struct RainbowBorderOverlay: View {
    let dockSize: CGSize
    let cornerSize: CGFloat = 15.0
    private let lineWidth: CGFloat = 1

    var body: some View {
        TimelineView(.animation) { context in
            let hueShift = context.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: 5) / 5

            RoundedRectangle(cornerRadius: cornerSize)
                .stroke(
                    AngularGradient(
                        colors: rainbowColors(offset: hueShift),
                        center: .center
                    ),
                    lineWidth: lineWidth
                )
                .allowsHitTesting(false)
        }
    }

    /// Generates rainbow colors with a rotating hue offset for continuous animation.
    private func rainbowColors(offset: Double) -> [Color] {
        let count = 12
        return (0...count).map { i in
            let hue = (Double(i) / Double(count) + offset).truncatingRemainder(dividingBy: 1.0)
            return Color(hue: hue, saturation: 0.8, brightness: 0.9)
        }
    }
}
