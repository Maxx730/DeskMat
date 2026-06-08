import SwiftUI

struct CloudsView: View {
    let weatherCode: Int
    let date: Date
    let skyColor: Color

    private static let cycleDuration: Double = 60  // seconds per full panel width

    var body: some View {
        Canvas { context, size in
            let count = cloudCount(for: weatherCode)
            guard count > 0 else { return }
            let elapsed = CGFloat(date.timeIntervalSinceReferenceDate)
            drawClouds(&context, size: size, count: count, elapsed: elapsed)
        }
        .allowsHitTesting(false)
    }

    // Maps WMO weather code to 0–5 visible clouds.
    private func cloudCount(for code: Int) -> Int {
        switch code {
        case 0:          return 3   // always show for now
        case 1:          return 1
        case 2:          return 2
        case 3:          return 5
        case 45, 48:     return 3
        case 51, 53, 55: return 3
        case 56, 57:     return 3
        case 61, 63, 65: return 4
        case 66, 67:     return 4
        case 71, 73, 75: return 3
        case 77:         return 3
        case 80, 81, 82: return 4
        case 85, 86:     return 3
        case 95:         return 5
        case 96, 99:     return 5
        default:         return 3
        }
    }

    private func drawClouds(_ context: inout GraphicsContext, size: CGSize, count: Int, elapsed: CGFloat) {
        let w = size.width
        let h = size.height

        // Ordered closest → most distant. First `count` entries are drawn.
        // (x1, x2, y, thickness, speed, brightness)
        let clouds: [(x1: CGFloat, x2: CGFloat, y: CGFloat, t: CGFloat, speed: CGFloat, brightness: Double)] = [
            (w * 0.20, w * 0.58, h * 0.24, 12, 1.00, 1.00),  // near,  fast,  bright
            (w * 0.55, w * 0.90, h * 0.20,  9, 0.80, 0.92),  // near-mid
            (w * 0.05, w * 0.35, h * 0.18,  7, 0.60, 0.82),  // mid
            (w * 0.40, w * 0.75, h * 0.15,  5, 0.45, 0.72),  // mid-far
            (w * 0.07, w * 0.30, h * 0.12,  3, 0.30, 0.65),  // distant, slow, dark
        ]

        let ns = NSColor(skyColor).usingColorSpace(.deviceRGB) ?? .white
        let sky = (r: ns.redComponent, g: ns.greenComponent, b: ns.blueComponent)
        let pixelsPerSecond = w / CGFloat(Self.cycleDuration)

        for cloud in clouds.prefix(count).reversed() {
            let cloudOffset = (elapsed * pixelsPerSecond * cloud.speed)
                .truncatingRemainder(dividingBy: w)
            let t = cloud.brightness
            let blended = Color(red:   sky.r + (1 - sky.r) * t,
                                green: sky.g + (1 - sky.g) * t,
                                blue:  sky.b + (1 - sky.b) * t)
            let shading = GraphicsContext.Shading.color(blended)
            for shift in [CGFloat(0), w] {
                stroke(&context,
                       x1: cloud.x1 - cloudOffset + shift,
                       x2: cloud.x2 - cloudOffset + shift,
                       y: cloud.y,
                       thickness: cloud.t,
                       shading: shading)
            }
        }
    }

    private func stroke(_ context: inout GraphicsContext,
                        x1: CGFloat, x2: CGFloat, y: CGFloat,
                        thickness: CGFloat,
                        shading: GraphicsContext.Shading) {
        var path = Path()
        path.move(to: CGPoint(x: x1, y: y))
        path.addLine(to: CGPoint(x: x2, y: y))
        context.stroke(path, with: shading,
                       style: StrokeStyle(lineWidth: thickness, lineCap: .round))
    }
}
