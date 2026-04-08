import SwiftUI

struct ClockWidget: View {
    static let cellCount = 1
    @AppStorage("showLabels") private var showLabels = true

    var body: some View {
        VStack(spacing: 10) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                DockWidget {
                    AnalogClockFace(date: context.date)
                }
            }
            .onTapGesture {
                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.clock") {
                    NSWorkspace.shared.open(url)
                }
            }
            if showLabels {
                Text(Strings.Widgets.clock)
                    .font(.caption2)
                    .lineLimit(1)
                    .frame(width: DockWidget<EmptyView>.width(for: Self.cellCount))
                    .truncationMode(.tail)
            }
        }
    }
}

// MARK: - Analog Clock Face
//
// Implemented as a single Canvas draw call rather than a SwiftUI view hierarchy.
// The previous GeometryReader + ZStack + ForEach + ClockHand views triggered a
// full layout pass every second. Canvas draws everything imperatively in one pass
// with no view diffing or layout overhead.

private struct AnalogClockFace: View {
    let date: Date

    var body: some View {
        Canvas { context, size in
            let dim    = min(size.width, size.height)
            let center = CGPoint(x: size.width / 2, y: size.height / 2)

            let calendar = Calendar.current
            let sec  = Double(calendar.component(.second, from: date))
            let min  = Double(calendar.component(.minute, from: date)) + sec / 60
            let hour = Double(calendar.component(.hour,   from: date)).truncatingRemainder(dividingBy: 12) + min / 60

            // Hour markers
            for i in 0..<12 {
                let angle = Double(i) / 12.0 * .pi * 2 - .pi / 2
                let mr = dim * 0.04
                let mx = center.x + CGFloat(cos(angle)) * dim * 0.44
                let my = center.y + CGFloat(sin(angle)) * dim * 0.44
                context.fill(
                    Path(ellipseIn: CGRect(x: mx - mr, y: my - mr, width: mr * 2, height: mr * 2)),
                    with: .color(.white.opacity(0.3))
                )
            }

            // Hands
            let handWidth = dim * 0.01
            func drawHand(fraction: Double, outOf: Double, length: CGFloat, color: Color) {
                let angle = fraction / outOf * .pi * 2 - .pi / 2
                var path = Path()
                path.move(to: center)
                path.addLine(to: CGPoint(x: center.x + CGFloat(cos(angle)) * length,
                                         y: center.y + CGFloat(sin(angle)) * length))
                context.stroke(path, with: .color(color),
                               style: StrokeStyle(lineWidth: handWidth, lineCap: .round))
            }
            drawHand(fraction: hour, outOf: 12, length: dim * 0.27, color: .white.opacity(0.6))
            drawHand(fraction: min,  outOf: 60, length: dim * 0.36, color: .white.opacity(0.6))
            drawHand(fraction: sec,  outOf: 60, length: dim * 0.38, color: .red)

            // Center dot
            let outerR = dim * 0.05
            let innerR = dim * 0.025
            context.fill(Path(ellipseIn: CGRect(x: center.x - outerR, y: center.y - outerR,
                                                width: outerR * 2,    height: outerR * 2)), with: .color(.white))
            context.fill(Path(ellipseIn: CGRect(x: center.x - innerR, y: center.y - innerR,
                                                width: innerR * 2,    height: innerR * 2)), with: .color(.black))
        }
        .padding(6)
    }
}
