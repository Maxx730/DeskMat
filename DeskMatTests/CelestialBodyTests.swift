import Testing
import CoreGraphics
import Foundation
@testable import DeskMat

struct CelestialBodyTests {

    private let center = CGPoint(x: 50, y: 50)
    private let orbitR: CGFloat = 44

    private func date(hour: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date()
    }

    // MARK: - Basic shape

    @Test func bodiesReturnsTwoBodies() {
        let bodies = CelestialBody.bodies(for: date(hour: 12), center: center, orbitR: orbitR)
        #expect(bodies.count == 2)
    }

    @Test func bodiesIncludeSunAndMoon() {
        let bodies = CelestialBody.bodies(for: date(hour: 12), center: center, orbitR: orbitR)
        #expect(bodies.contains(where: { $0.kind == .sun }))
        #expect(bodies.contains(where: { $0.kind == .moon }))
    }

    @Test func sunRadiusIsFixed() {
        let bodies = CelestialBody.bodies(for: date(hour: 12), center: center, orbitR: orbitR)
        let sun = bodies.first(where: { $0.kind == .sun })
        #expect(sun?.radius == 6)
    }

    @Test func moonRadiusIsFixed() {
        let bodies = CelestialBody.bodies(for: date(hour: 12), center: center, orbitR: orbitR)
        let moon = bodies.first(where: { $0.kind == .moon })
        #expect(moon?.radius == 5)
    }

    // MARK: - Orbital geometry

    @Test func sunAndMoonAreOppositeOnOrbit() {
        // Their position vectors from center should sum to zero (diametrically opposite).
        let bodies = CelestialBody.bodies(for: date(hour: 12), center: center, orbitR: orbitR)
        guard let sun  = bodies.first(where: { $0.kind == .sun }),
              let moon = bodies.first(where: { $0.kind == .moon }) else {
            Issue.record("Missing sun or moon")
            return
        }
        let dx = (sun.position.x - center.x) + (moon.position.x - center.x)
        let dy = (sun.position.y - center.y) + (moon.position.y - center.y)
        #expect(abs(dx) < 0.001)
        #expect(abs(dy) < 0.001)
    }

    @Test func sunAndMoonAreOppositeAtMidnight() {
        let bodies = CelestialBody.bodies(for: date(hour: 0), center: center, orbitR: orbitR)
        guard let sun  = bodies.first(where: { $0.kind == .sun }),
              let moon = bodies.first(where: { $0.kind == .moon }) else {
            Issue.record("Missing sun or moon")
            return
        }
        let dx = (sun.position.x - center.x) + (moon.position.x - center.x)
        let dy = (sun.position.y - center.y) + (moon.position.y - center.y)
        #expect(abs(dx) < 0.001)
        #expect(abs(dy) < 0.001)
    }

    @Test func sunIsAtTopAtNoon() {
        // sunAngle at noon = π/2 − π = −π/2 → position directly above center
        let bodies = CelestialBody.bodies(for: date(hour: 12), center: center, orbitR: orbitR)
        guard let sun = bodies.first(where: { $0.kind == .sun }) else {
            Issue.record("No sun"); return
        }
        #expect(abs(sun.position.x - center.x) < 0.001)
        #expect(sun.position.y < center.y)
    }

    @Test func sunIsAtBottomAtMidnight() {
        // sunAngle at midnight = π/2 → position directly below center
        let bodies = CelestialBody.bodies(for: date(hour: 0), center: center, orbitR: orbitR)
        guard let sun = bodies.first(where: { $0.kind == .sun }) else {
            Issue.record("No sun"); return
        }
        #expect(abs(sun.position.x - center.x) < 0.001)
        #expect(sun.position.y > center.y)
    }

    @Test func bodiesLieOnOrbitCircle() {
        // Every body should be exactly orbitR away from center.
        for hour in [0, 6, 12, 18] {
            let bodies = CelestialBody.bodies(for: date(hour: hour), center: center, orbitR: orbitR)
            for body in bodies {
                let dx = body.position.x - center.x
                let dy = body.position.y - center.y
                let dist = sqrt(dx * dx + dy * dy)
                #expect(abs(dist - orbitR) < 0.001, "hour \(hour), kind \(body.kind)")
            }
        }
    }

    @Test func sunMovesWithTime() {
        let bodies6  = CelestialBody.bodies(for: date(hour: 6),  center: center, orbitR: orbitR)
        let bodies18 = CelestialBody.bodies(for: date(hour: 18), center: center, orbitR: orbitR)
        guard let sun6  = bodies6.first(where:  { $0.kind == .sun }),
              let sun18 = bodies18.first(where: { $0.kind == .sun }) else {
            Issue.record("Missing sun"); return
        }
        #expect(sun6.position != sun18.position)
    }
}
