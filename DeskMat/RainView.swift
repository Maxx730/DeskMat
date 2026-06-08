import SwiftUI

struct RainView: View {
    let weatherCode: Int
    let date: Date

    private struct Drop {
        let x:       CGFloat   // normalised 0–1, scaled by width in Canvas
        let speed:   CGFloat   // points per second
        let length:  CGFloat   // stroke length in points
        let opacity: Double
        let phase:   CGFloat   // normalised 0–1, scaled by height in Canvas
    }

    // One array per intensity level, computed once at launch — never per-frame.
    private static let dropsByIntensity: [[Drop]] = [
        [],
        makeDrops(count: 25, seed: 0xA1B2C3D4E5F60001, speedLo: 60,  speedHi: 90,  lenLo: 4,  lenHi: 6),
        makeDrops(count: 40, seed: 0xA1B2C3D4E5F60002, speedLo: 80,  speedHi: 120, lenLo: 5,  lenHi: 8),
        makeDrops(count: 60, seed: 0xA1B2C3D4E5F60003, speedLo: 110, speedHi: 160, lenLo: 6,  lenHi: 10),
        makeDrops(count: 80, seed: 0xA1B2C3D4E5F60004, speedLo: 140, speedHi: 200, lenLo: 7,  lenHi: 12),
    ]

    var body: some View {
        let drops = Self.dropsByIntensity[Self.intensity(for: weatherCode)]
        Canvas { context, size in
            guard !drops.isEmpty else { return }
            let elapsed = CGFloat(date.timeIntervalSinceReferenceDate)
            for drop in drops {
                let x  = drop.x * size.width
                let wrapHeight = size.height + drop.length
                let y  = (elapsed * drop.speed + drop.phase * size.height)
                    .truncatingRemainder(dividingBy: wrapHeight)
                var path = Path()
                path.move(to:    CGPoint(x: x,     y: y))
                path.addLine(to: CGPoint(x: x + 2, y: y + drop.length))
                context.stroke(path,
                               with: .color(.white.opacity(drop.opacity)),
                               style: StrokeStyle(lineWidth: 1, lineCap: .round))
            }
        }
        .allowsHitTesting(false)
    }

    private static func intensity(for code: Int) -> Int {
        switch code {
        case 51, 53, 55:        return 1
        case 56, 57, 61, 63:    return 2
        case 65, 66, 67,
             80, 81, 82:        return 3
        case 95, 96, 99:        return 4
        default:                return 3   // force visible for preview
        }
    }

    private static func makeDrops(count: Int, seed: UInt64,
                                   speedLo: Double, speedHi: Double,
                                   lenLo: Double,   lenHi: Double) -> [Drop] {
        var s = seed
        func rand() -> Double {
            s = s &* 6364136223846793005 &+ 1442695040888963407
            return Double(s >> 33) / Double(1 << 31)
        }
        return (0..<count).map { _ in
            Drop(x:       CGFloat(rand()),
                 speed:   CGFloat(speedLo  + rand() * (speedHi - speedLo)),
                 length:  CGFloat(lenLo    + rand() * (lenHi   - lenLo)),
                 opacity: 0.25 + rand() * 0.45,
                 phase:   CGFloat(rand()))
        }
    }
}
