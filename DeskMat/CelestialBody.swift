import CoreGraphics
import Foundation

struct CelestialBody {

    enum Kind { case sun, moon }

    let kind:     Kind
    let position: CGPoint
    let radius:   CGFloat

    // Returns one sun and one moon positioned on the orbit circle for the given time.
    static func bodies(for date: Date, center: CGPoint, orbitR: CGFloat) -> [CelestialBody] {
        let comps = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
        let hour  = Double(comps.hour   ?? 0)
                  + Double(comps.minute ?? 0) / 60
                  + Double(comps.second ?? 0) / 3600

        // Sun at top (−π/2 in y-down coords) at noon, bottom at midnight.
        let sunAngle  = .pi / 2 - (hour / 24.0) * .pi * 2
        let moonAngle = sunAngle + .pi

        return [
            CelestialBody(kind: .sun,
                          position: point(angle: sunAngle,  center: center, radius: orbitR),
                          radius: 6),
            CelestialBody(kind: .moon,
                          position: point(angle: moonAngle, center: center, radius: orbitR),
                          radius: 5),
        ]
    }

    private static func point(angle: Double, center: CGPoint, radius: CGFloat) -> CGPoint {
        CGPoint(x: center.x + radius * CGFloat(cos(angle)),
                y: center.y + radius * CGFloat(sin(angle)))
    }
}
