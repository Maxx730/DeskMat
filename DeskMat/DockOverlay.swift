import SwiftUI

struct DockOverlay: View {
    let dockSize: CGSize
    let mousePosition: CGPoint?
    let cornerSize: CGFloat = 16.0
    private let circleSize: CGFloat = 3

    /// Path inset by the circle radius so the circle never extends beyond the view bounds.
    var outlinePath: Path {
        let inset = circleSize / 2
        let rect = CGRect(
            x: inset,
            y: inset,
            width: dockSize.width - circleSize,
            height: dockSize.height - circleSize
        )
        let adjustedCorner = max(cornerSize - inset, 0)
        return Path { path in
            path.addRoundedRect(in: rect, cornerSize: CGSize(width: adjustedCorner, height: adjustedCorner))
        }
    }

    var body: some View {
        if let mouse = mousePosition {
            let fraction = closestFraction(to: mouse)
            let pos = point(at: fraction)
            let rotation = angle(at: fraction)

            // Glow layer — larger, blurred capsule behind
            Capsule()
                .fill(
                    RadialGradient(
                        colors: [.red.opacity(0.6), .red.opacity(0)],
                        center: .center,
                        startRadius: 0,
                        endRadius: circleSize * 4
                    )
                )
                .frame(width: circleSize * 5, height: circleSize * 3)
                .rotationEffect(rotation)
                .position(pos)
                .blur(radius: 4)

            // Core pill
            Capsule()
                .fill(ColorUtils.darkened(.red))
                .stroke(.red, lineWidth: 1)
                .frame(width: circleSize * 2.5, height: circleSize)
                .rotationEffect(rotation)
                .position(pos)
        }
    }

    /// Returns the point on the outline path at a given fraction (0.0 = start, 1.0 = end).
    func point(at fraction: CGFloat) -> CGPoint {
        let clamped = min(max(fraction, 0), 0.999)
        let trimmed = outlinePath.trimmedPath(from: clamped, to: clamped + 0.001)
        return CGPoint(x: trimmed.boundingRect.midX, y: trimmed.boundingRect.midY)
    }

    /// Returns the rotation angle so the pill aligns tangent to the path at the given fraction.
    func angle(at fraction: CGFloat) -> Angle {
        let delta: CGFloat = 0.005
        let a = point(at: fraction)
        let b = point(at: fraction + delta)
        let dx = b.x - a.x
        let dy = b.y - a.y
        return Angle(radians: atan2(Double(dy), Double(dx)))
    }

    /// Finds the fraction along the path closest to the given point by sampling.
    func closestFraction(to target: CGPoint) -> CGFloat {
        let steps = 200
        var bestFraction: CGFloat = 0
        var bestDistance: CGFloat = .infinity

        for i in 0...steps {
            let f = CGFloat(i) / CGFloat(steps) * 0.999
            let p = point(at: f)
            let dx = p.x - target.x
            let dy = p.y - target.y
            let dist = dx * dx + dy * dy
            if dist < bestDistance {
                bestDistance = dist
                bestFraction = f
            }
        }
        return bestFraction
    }
}
