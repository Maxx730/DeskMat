import SwiftUI

struct ClockWidget: View {
    static let cellCount = 1
    @AppStorage("showLabels")  private var showLabels  = true
    @AppStorage("clockStyle")  private var clockStyle: ClockStyle = .system

    var body: some View {
        VStack(spacing: 10) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                DockWidget(backgroundColor: clockStyle == .flat ? Color(red: 0.702, green: 0.702, blue: 0.702) : nil) {
                    AnalogClockFace(date: context.date, style: clockStyle)
                }
            }
            .onTapGesture {
                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") {
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
    let style: ClockStyle

    var body: some View {
        Canvas(renderer: render)
    }

    private func render(context: inout GraphicsContext, size: CGSize) {
        let dim    = min(size.width, size.height)
        let center = CGPoint(x: size.width / 2, y: size.height / 2)

        let calendar = Calendar.current
        let sec  = Double(calendar.component(.second, from: date))
        let min  = Double(calendar.component(.minute, from: date)) + sec / 60
        let hour = Double(calendar.component(.hour,   from: date)).truncatingRemainder(dividingBy: 12) + min / 60

        switch style {
        case .flat:
            renderFlat(&context, center: center, dim: dim, sec: sec, min: min, hour: hour)
        case .system:
            renderSystem(&context, center: center, dim: dim, sec: sec, min: min, hour: hour)
        }
    }

    private func renderFlat(_ context: inout GraphicsContext, center: CGPoint,
                             dim: CGFloat, sec: Double, min: Double, hour: Double) {
        // Background — gray shell color fills the entire canvas
        let bgR = dim * 0.55
        context.fill(
            Path(ellipseIn: CGRect(x: center.x - bgR, y: center.y - bgR, width: bgR * 2, height: bgR * 2)),
            with: .color(Color(red: 0.702, green: 0.702, blue: 0.702))
        )

        // Ring just outside the hour dot orbit
        let flatRingR = dim * 0.45

        // White inner clock face — sits just inside the ring's inner edge
        let faceR = flatRingR - dim * 0.02
        context.fill(
            Path(ellipseIn: CGRect(x: center.x - faceR, y: center.y - faceR, width: faceR * 2, height: faceR * 2)),
            with: .color(.white)
        )
        context.stroke(
            Path(ellipseIn: CGRect(x: center.x - flatRingR, y: center.y - flatRingR,
                                   width: flatRingR * 2, height: flatRingR * 2)),
            with: .color(.gray),
            lineWidth: dim * 0.005
        )

        // Hour markers
        for i in 0..<12 {
            let angle = Double(i) / 12.0 * .pi * 2 - .pi / 2
            let mr = dim * 0.025
            let mx = center.x + CGFloat(cos(angle)) * dim * 0.34
            let my = center.y + CGFloat(sin(angle)) * dim * 0.34
            context.fill(
                Path(ellipseIn: CGRect(x: mx - mr, y: my - mr, width: mr * 2, height: mr * 2)),
                with: .color(.black.opacity(0.15))
            )
        }

        let hw = dim * 0.02
        drawHand(&context, center: center, fraction: hour, outOf: 12, length: dim * 0.27, width: hw,       color: .black)
        drawHand(&context, center: center, fraction: min,  outOf: 60, length: dim * 0.36, width: hw,       color: .black)
        drawHand(&context, center: center, fraction: sec,  outOf: 60, length: dim * 0.38, width: hw * 0.6, color: .red)

        let outerR = dim * 0.05
        let innerR = dim * 0.025
        context.fill(Path(ellipseIn: CGRect(x: center.x - outerR, y: center.y - outerR, width: outerR * 2, height: outerR * 2)), with: .color(.black))
        context.fill(Path(ellipseIn: CGRect(x: center.x - innerR, y: center.y - innerR, width: innerR * 2, height: innerR * 2)), with: .color(.red))
    }

    private func renderSystem(_ context: inout GraphicsContext, center: CGPoint,
                               dim: CGFloat, sec: Double, min: Double, hour: Double) {
        // Ring just outside the hour dot orbit
        let sysRingR = dim * 0.57
        context.stroke(
            Path(ellipseIn: CGRect(x: center.x - sysRingR, y: center.y - sysRingR,
                                   width: sysRingR * 2, height: sysRingR * 2)),
            with: .color(.gray.opacity(0.25)),
            lineWidth: dim * 0.012
        )

        // Hour markers
        for i in 0..<12 {
            let angle = Double(i) / 12.0 * .pi * 2 - .pi / 2
            let mr = dim * 0.04
            let mx = center.x + CGFloat(cos(angle)) * dim * 0.44
            let my = center.y + CGFloat(sin(angle)) * dim * 0.44
            context.fill(
                Path(ellipseIn: CGRect(x: mx - mr, y: my - mr, width: mr, height: mr)),
                with: .color(.white.opacity(0.3))
            )
        }

        let hw = dim * 0.01
        drawHand(&context, center: center, fraction: hour, outOf: 12, length: dim * 0.27, width: hw, color: .white.opacity(0.6))
        drawHand(&context, center: center, fraction: min,  outOf: 60, length: dim * 0.36, width: hw, color: .white.opacity(0.6))
        drawHand(&context, center: center, fraction: sec,  outOf: 60, length: dim * 0.38, width: hw, color: .red)

        let outerR = dim * 0.05
        let innerR = dim * 0.025
        context.fill(Path(ellipseIn: CGRect(x: center.x - outerR, y: center.y - outerR, width: outerR * 2, height: outerR * 2)), with: .color(.white))
        context.fill(Path(ellipseIn: CGRect(x: center.x - innerR, y: center.y - innerR, width: innerR * 2, height: innerR * 2)), with: .color(.black))
    }

    private func drawHand(_ context: inout GraphicsContext, center: CGPoint,
                           fraction: Double, outOf: Double,
                           length: CGFloat, width: CGFloat, color: Color) {
        let angle = fraction / outOf * .pi * 2 - .pi / 2
        var path = Path()
        path.move(to: center)
        path.addLine(to: CGPoint(x: center.x + CGFloat(cos(angle)) * length,
                                 y: center.y + CGFloat(sin(angle)) * length))
        context.stroke(path, with: .color(color),
                       style: StrokeStyle(lineWidth: width, lineCap: .round))
    }
}
