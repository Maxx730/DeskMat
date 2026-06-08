import SwiftUI

struct SystemWidget: View {
    private var cellCount: Int { metric.cellCount }

    @Environment(SystemMonitorService.self) private var monitor
    @AppStorage("showLabels")      private var showLabels = true
    @AppStorage("sysWidgetMetric") private var metric: SystemMetric = .cpu

    var body: some View {
        VStack(spacing: 10) {
            DockWidget(cells: cellCount,
                       backgroundColor: metric == .cpu     ? Color(red: 0.0, green: 0.08, blue: 0.03) :
                                        metric == .ram     ? .clear :
                                        metric == .network ? Color(hex: "#050a14") : nil) {
                switch metric {
                case .cpu:     CPUView(percent: monitor.cpuPercent, history: monitor.cpuHistory)
                case .ram:     RAMView(used: monitor.ramUsedGB, total: monitor.ramTotalGB)
                case .network:
                    HStack(spacing: 0) {
                        NetPanelView(history: monitor.netInHistory,  strokeColor: Color(hex: "#4a9eff"), direction: "↓")
                        Rectangle()
                            .fill(Color.white.opacity(0.10))
                            .frame(width: 1)
                        NetPanelView(history: monitor.netOutHistory, strokeColor: Color(hex: "#ff4a4a"), direction: "↑")
                    }
                }
            }
            .clipShape(RAMChipShape(showNotches: metric == .ram))
            if showLabels {
                Text(metric.rawValue)
                    .font(.caption2)
                    .lineLimit(1)
                    .frame(width: DockWidget<EmptyView>.width(for: cellCount))
                    .truncationMode(.tail)
            }
        }
        .onAppear  { monitor.start() }
        .onDisappear { monitor.stop() }
    }
}

// MARK: - CPU

private struct CPUView: View {
    let percent: Double
    let history: [Double]

    var body: some View {
        ZStack(alignment: .top) {
            CPUGraphView(history: history)
            VStack(spacing: 1) {
                Text(Strings.Widgets.SystemMonitor.cpuHeader)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(red: 0.2, green: 1.0, blue: 0.3, opacity: 0.9))
                Text(Strings.Widgets.SystemMonitor.cpuPercent(Int(percent * 100)))
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color(red: 0.2, green: 1.0, blue: 0.3, opacity: 0.9))
            }
            .padding(.top, 6)
        }
    }
}

// MARK: - RAM

private struct RAMView: View {
    let used: Double
    let total: Double

    private var fraction: Double {
        total > 0 ? min(used / total, 1.0) : 0
    }

    var body: some View {
        ImageProgressView(image: Image("ram"), value: fraction, axis: .horizontal)
            .animation(.easeOut(duration: 0.4), value: fraction)
    }
}


// MARK: - Half Circle Meter

/// Analog half-circle gauge. Conforms to Animatable so SwiftUI interpolates
/// `value` smoothly between updates without any extra @State machinery.
private struct HalfCircleMeter: View, Animatable {

    /// Normalised fill level, 0.0 – 1.0.
    var value: Double

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Canvas(renderer: render)
    }

    // MARK: - Canvas renderer

    private func render(context: inout GraphicsContext, size: CGSize) {
        // Stroke width scales with the smaller dimension so the arc looks
        // proportional at any size the caller chooses.
        let strokeWidth = min(size.width, size.height * 2) * 0.12
        // Center sits at the bottom edge so the flat side of the D rests there.
        let center = CGPoint(x: size.width / 2, y: size.height)
        let radius = min(size.width / 2, size.height) - strokeWidth / 2 - 1

        guard radius > 0 else { return }

        let startAngle = Angle.degrees(90)   // 9 o'clock (left edge)

        // Background track — full 180° arc from left (180°) to right (0°),
        // drawn clockwise in SwiftUI's Y-down coordinate space so it passes
        // through 270° (up / top of the view).
        var track = Path()
        track.addArc(center: center, radius: radius,
                     startAngle: startAngle, endAngle: .degrees(0),
                     clockwise: true)
        context.stroke(track,
                       with: .color(.white.opacity(0.25)),
                       style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round))

        // Value arc — sweeps clockwise from the left edge.
        // endAngle = 180 + value × 180 maps [0,1] → [180°,360°/0°].
        let clamped = max(0, min(1, value))
        guard clamped > 0.001 else { return }

        var fill = Path()
        fill.addArc(center: center, radius: radius,
                    startAngle: startAngle,
                    endAngle: .degrees(180 + clamped * 180),
                    clockwise: true)
        context.stroke(fill,
                       with: .color(.red),
                       style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round))
    }

    // MARK: - Color

    /// White below 60%, blends through orange to red above 80%.
    private func meterColor(for v: Double) -> Color {
        if v < 0.6 {
            return .white.opacity(0.85)
        } else if v < 0.8 {
            let t = (v - 0.6) / 0.2          // 0 → 1 across the 60–80% band
            return Color(red: 1.0, green: 1.0 - t * 0.45, blue: 1.0 - t, opacity: 0.85)
        } else {
            let t = (v - 0.8) / 0.2          // 0 → 1 across the 80–100% band
            return Color(red: 1.0, green: 0.55 - t * 0.55, blue: 0.0, opacity: 0.85)
        }
    }
}

// MARK: - CPU Waveform Graph

private struct CPUGraphView: View {
    let history: [Double]   // newest-first, 0.0–1.0

    var body: some View {
        Canvas { context, size in
            drawGridLines(context: &context, size: size)
            guard history.count >= 2 else { return }
            let pts = chartPoints(in: size)
            let curve = smoothCurve(through: pts)
            var filled = curve
            filled.addLine(to: CGPoint(x: size.width, y: size.height))
            filled.addLine(to: CGPoint(x: 0, y: size.height))
            filled.closeSubpath()
            context.fill(filled, with: .color(Color(red: 0.15, green: 0.75, blue: 0.22, opacity: 0.18)))
            context.stroke(curve,
                           with: .color(.green),
                           style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
    }

    private func drawGridLines(context: inout GraphicsContext, size: CGSize) {
        let lineColor = GraphicsContext.Shading.color(Color(red: 0.06, green: 0.20, blue: 0.08))
        let hDivisions = 4
        let vDivisions = 5
        for i in 1..<hDivisions {
            let y = size.height * CGFloat(i) / CGFloat(hDivisions)
            var path = Path()
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
            context.stroke(path, with: lineColor, lineWidth: 0.5)
        }
        for i in 1..<vDivisions {
            let x = size.width * CGFloat(i) / CGFloat(vDivisions)
            var path = Path()
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: size.height))
            context.stroke(path, with: lineColor, lineWidth: 0.5)
        }
    }

    // Returns points ordered left (oldest) → right (newest).
    // A floor of 0.35 keeps the baseline near the vertical center even at 0% CPU.
    private func chartPoints(in size: CGSize) -> [CGPoint] {
        let n = history.count
        let floor: Double = 0.15
        return (0..<n).map { i in
            let x = CGFloat(i) / CGFloat(max(n - 1, 1)) * size.width
            let raw = history[n - 1 - i]
            let display = floor + raw * (1.0 - floor)
            let y = size.height * (1.0 - display)
            return CGPoint(x: x, y: y)
        }
    }

    private func smoothCurve(through pts: [CGPoint]) -> Path {
        guard pts.count >= 2 else { return Path() }
        var path = Path()
        path.move(to: pts[0])
        for pt in pts.dropFirst() { path.addLine(to: pt) }
        return path
    }
}

// MARK: - Network Panel

private struct NetPanelView: View {
    let history:     [Double]   // newest-first, KB/s
    let strokeColor: Color
    let direction:   String     // "↓" or "↑"

    private static let minimumPeak: Double = 128

    private var formattedRate: String {
        let v = history.first ?? 0
        return v >= 1024 ? String(format: "%.1f MB/s", v / 1024) : "\(Int(v)) KB/s"
    }

    var body: some View {
        ZStack {
            Canvas { context, size in
                let peak = max(history.max() ?? 0, Self.minimumPeak)
                drawGridLines(context: &context, size: size)
                guard history.count >= 2 else { return }
                let pts = chartPoints(history: history, peak: peak, in: size)
                let curve = linePath(through: pts)
                var filled = curve
                filled.addLine(to: CGPoint(x: size.width, y: size.height))
                filled.addLine(to: CGPoint(x: 0,          y: size.height))
                filled.closeSubpath()
                context.fill(filled, with: .color(strokeColor.opacity(0.18)))
                context.stroke(curve, with: .color(strokeColor),
                               style: StrokeStyle(lineWidth: 1.0, lineCap: .round, lineJoin: .round))
            }
            VStack(spacing: 0) {
                Text(direction)
                    .foregroundStyle(strokeColor.opacity(0.85))
                Spacer()
                Text(formattedRate)
                    .foregroundStyle(strokeColor.opacity(0.60))
            }
            .font(.system(size: 8, weight: .semibold, design: .monospaced))
            .frame(maxWidth: .infinity)
            .padding(4)
        }
    }

    private func drawGridLines(context: inout GraphicsContext, size: CGSize) {
        let shading = GraphicsContext.Shading.color(Color(hex: "#0d1828"))
        let hDivisions = 8
        let vDivisions = 6
        for i in 1..<hDivisions {
            let y = size.height * CGFloat(i) / CGFloat(hDivisions)
            var p = Path(); p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: size.width, y: y))
            context.stroke(p, with: shading, lineWidth: 0.5)
        }
        for i in 1..<vDivisions {
            let x = size.width * CGFloat(i) / CGFloat(vDivisions)
            var p = Path(); p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: size.height))
            context.stroke(p, with: shading, lineWidth: 0.5)
        }
    }

    private func chartPoints(history: [Double], peak: Double, in size: CGSize) -> [CGPoint] {
        let n = history.count
        let floor: Double = 0.265
        return (0..<n).map { i in
            let x = CGFloat(i) / CGFloat(max(n - 1, 1)) * size.width
            let normalised = min(history[n - 1 - i] / peak, 1.0)
            let display = floor + normalised * (1.0 - floor)
            return CGPoint(x: x, y: size.height * (1.0 - display))
        }
    }

    private func linePath(through pts: [CGPoint]) -> Path {
        guard pts.count >= 2 else { return Path() }
        var path = Path()
        path.move(to: pts[0])
        for pt in pts.dropFirst() { path.addLine(to: pt) }
        return path
    }
}

// MARK: - RAM Chip Shape

/// Rounded rectangle with two concave semicircular notches cut into the left and right edges,
/// matching the alignment keys on a physical RAM DIMM. When `showNotches` is false it
/// behaves identically to `RoundedRectangle(cornerRadius: 10)`.
private struct RAMChipShape: Shape {
    var showNotches: Bool
    var cornerRadius: CGFloat = 10
    var notchRadius:  CGFloat = 9

    func path(in rect: CGRect) -> Path {
        guard showNotches else {
            return Path(roundedRect: rect, cornerRadius: cornerRadius)
        }

        var p = Path()
        let cr   = cornerRadius
        let nr   = notchRadius
        let midY = rect.midY - 8

        // ── top edge (left corner → right corner) ──
        p.move(to: CGPoint(x: rect.minX + cr, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - cr, y: rect.minY))
        p.addQuadCurve(to:      CGPoint(x: rect.maxX,      y: rect.minY + cr),
                       control: CGPoint(x: rect.maxX,      y: rect.minY))

        // ── right edge: top → notch top ──
        p.addLine(to: CGPoint(x: rect.maxX, y: midY - nr))

        // ── right notch: concave arc from top to bottom, bulging leftward ──
        // startAngle 270° = point directly above centre, going counterclockwise
        // through 180° (leftward) to 90° = point directly below centre
        p.addArc(center:     CGPoint(x: rect.maxX, y: midY),
                 radius:     nr,
                 startAngle: .degrees(270),
                 endAngle:   .degrees(90),
                 clockwise:  false)

        // ── right edge: notch bottom → bottom-right corner ──
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - cr))
        p.addQuadCurve(to:      CGPoint(x: rect.maxX - cr, y: rect.maxY),
                       control: CGPoint(x: rect.maxX,      y: rect.maxY))

        // ── bottom edge (right → left) ──
        p.addLine(to: CGPoint(x: rect.minX + cr, y: rect.maxY))
        p.addQuadCurve(to:      CGPoint(x: rect.minX, y: rect.maxY - cr),
                       control: CGPoint(x: rect.minX, y: rect.maxY))

        // ── left edge: bottom → notch bottom ──
        p.addLine(to: CGPoint(x: rect.minX, y: midY + nr))

        // ── left notch: concave arc from bottom to top, bulging rightward ──
        // startAngle 90° = below centre, clockwise through 0° (rightward) to 270°
        p.addArc(center:     CGPoint(x: rect.minX, y: midY),
                 radius:     nr,
                 startAngle: .degrees(90),
                 endAngle:   .degrees(270),
                 clockwise:  true)

        // ── left edge: notch top → top-left corner ──
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + cr))
        p.addQuadCurve(to:      CGPoint(x: rect.minX + cr, y: rect.minY),
                       control: CGPoint(x: rect.minX,      y: rect.minY))

        p.closeSubpath()
        return p
    }
}
