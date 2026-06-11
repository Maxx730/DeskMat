import SwiftUI

struct CelestialDialView: View {
    let date: Date

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2 + (size.height / 2) - 8)
            let orbitR: CGFloat = 44

            // Subtle orbit guide ring
            context.stroke(
                Path(ellipseIn: CGRect(x: center.x - orbitR, y: center.y - orbitR,
                                       width: orbitR * 2, height: orbitR * 2)),
                with: .color(.white.opacity(0.2)),
                lineWidth: 0.5
            )

            for body in CelestialBody.bodies(for: date, center: center, orbitR: orbitR) {
                switch body.kind {
                case .sun:  drawSun(&context, body: body)
                case .moon: drawMoon(&context, body: body, date: date)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func drawSun(_ context: inout GraphicsContext, body: CelestialBody) {
        let r = body.radius
        let p = body.position

        // Glow ring
        context.stroke(
            Path(ellipseIn: CGRect(x: p.x - r - 3, y: p.y - r - 3,
                                   width: (r + 3) * 2, height: (r + 3) * 2)),
            with: .color(Color(red: 1.0, green: 0.85, blue: 0.20, opacity: 0.3)),
            lineWidth: 2.5
        )

        // Fill
        context.fill(
            Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
            with: .color(Color(red: 1.0, green: 0.85, blue: 0.20))
        )
    }

    private func drawMoon(_ context: inout GraphicsContext, body: CelestialBody, date: Date) {
        let r  = body.radius
        let p  = body.position

        // Full silver disk
        context.fill(
            Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
            with: .color(Color(white: 0.88))
        )
    }
}
