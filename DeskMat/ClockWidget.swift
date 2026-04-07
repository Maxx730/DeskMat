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

private struct AnalogClockFace: View {
    let date: Date

    private var calendar: Calendar { .current }

    private var seconds: Double {
        Double(calendar.component(.second, from: date))
    }
    private var minutes: Double {
        let m = Double(calendar.component(.minute, from: date))
        return m + seconds / 60
    }
    private var hours: Double {
        let h = Double(calendar.component(.hour, from: date)).truncatingRemainder(dividingBy: 12)
        return h + minutes / 60
    }

    var body: some View {
        GeometryReader { geo in
            let size = max(geo.size.width, geo.size.height)
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)

            ZStack {
                // Hour markers
                ForEach(0..<12, id: \.self) { i in
                    let angle = Angle(degrees: Double(i) / 12 * 360 - 90)
                    let r = size * 0.44
                    let markerLength = size * 0.04
                    let x = center.x + r * cos(angle.radians)
                    let y = center.y + r * sin(angle.radians)
                    Circle()
                        .fill(.white.opacity(0.3))
                        .frame(width: markerLength, height: markerLength)
                        .position(x: x, y: y)
                }

                // Hour hand
                ClockHand(
                    angle: .degrees(hours / 12 * 360 - 90),
                    length: size * 0.27,
                    width: size * 0.01,
                    color: .white.opacity(0.6)
                )

                // Minute hand
                ClockHand(
                    angle: .degrees(minutes / 60 * 360 - 90),
                    length: size * 0.36,
                    width: size * 0.01,
                    color: .white.opacity(0.6)
                )

                // Second hand
                ClockHand(
                    angle: .degrees(seconds / 60 * 360 - 90),
                    length: size * 0.38,
                    width: size * 0.01,
                    color: .red
                )

                // Center dot
                Circle()
                    .fill(.white)
                    .frame(width: size * 0.1, height: size * 0.1)
                Circle()
                    .fill(.black)
                    .frame(width: size * 0.05, height: size * 0.05)
            }
        }.padding(6)
    }
}

private struct ClockHand: View {
    let angle: Angle
    let length: CGFloat
    let width: CGFloat
    let color: Color

    var body: some View {
        Capsule()
            .fill(color)
            .frame(width: length, height: width)
            .offset(x: length / 2, y: 0)
            .rotationEffect(angle, anchor: .center)
    }
}
