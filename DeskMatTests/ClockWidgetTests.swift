import Testing
import Foundation
@testable import DeskMat

// MARK: - ClockWidget

struct ClockWidgetCellCountTests {

    @Test func cellCountIsOne() {
        #expect(ClockWidget.cellCount == 1)
    }
}

// MARK: - Hand angle formula
//
// drawHand uses: angle = (fraction / outOf) * 2π - π/2
// π/2 offset rotates 0 from the right (math default) to the top (12 o'clock).
// Tests verify the four cardinal positions for both hands.

struct ClockHandAngleTests {

    private func handAngle(fraction: Double, outOf: Double) -> Double {
        fraction / outOf * .pi * 2 - .pi / 2
    }

    // Hour hand — 12 positions
    @Test func hourHandAt12PointsUp() {
        let angle = handAngle(fraction: 0, outOf: 12)
        #expect(abs(angle - (-.pi / 2)) < 1e-10)
    }

    @Test func hourHandAt3PointsRight() {
        let angle = handAngle(fraction: 3, outOf: 12)
        #expect(abs(angle - 0) < 1e-10)
    }

    @Test func hourHandAt6PointsDown() {
        let angle = handAngle(fraction: 6, outOf: 12)
        #expect(abs(angle - .pi / 2) < 1e-10)
    }

    @Test func hourHandAt9PointsLeft() {
        let angle = handAngle(fraction: 9, outOf: 12)
        #expect(abs(angle - .pi) < 1e-10)
    }

    // Minute / second hand — 60 divisions
    @Test func minuteHandAt0PointsUp() {
        let angle = handAngle(fraction: 0, outOf: 60)
        #expect(abs(angle - (-.pi / 2)) < 1e-10)
    }

    @Test func minuteHandAt15PointsRight() {
        let angle = handAngle(fraction: 15, outOf: 60)
        #expect(abs(angle - 0) < 1e-10)
    }

    @Test func minuteHandAt30PointsDown() {
        let angle = handAngle(fraction: 30, outOf: 60)
        #expect(abs(angle - .pi / 2) < 1e-10)
    }

    @Test func minuteHandAt45PointsLeft() {
        let angle = handAngle(fraction: 45, outOf: 60)
        #expect(abs(angle - .pi) < 1e-10)
    }

    // Smoothing — minute carries seconds, hour carries minutes
    @Test func minuteValueIncludesSeconds() {
        // 30 min 30 sec → fraction = 30.5
        let min = 30.0 + 30.0 / 60.0
        let angle = handAngle(fraction: min, outOf: 60)
        let expected = handAngle(fraction: 30, outOf: 60)
        #expect(angle > expected) // 30.5 min is slightly past the 6 o'clock mark
    }

    @Test func hourValueIncludesMinutes() {
        // 3h 30min → fraction = 3.5
        let hour = 3.0 + 30.0 / 60.0
        let angleWithMinutes = handAngle(fraction: hour,  outOf: 12)
        let angleExact       = handAngle(fraction: 3.0,   outOf: 12)
        #expect(angleWithMinutes > angleExact)
    }

    // 12-hour wrap — hour 13 should resolve to 1
    @Test func hourWrapsAt12() {
        let h13 = (13.0).truncatingRemainder(dividingBy: 12)  // 1.0
        let angle13 = handAngle(fraction: h13, outOf: 12)
        let angle1  = handAngle(fraction: 1,   outOf: 12)
        #expect(abs(angle13 - angle1) < 1e-10)
    }
}
