import Testing
import Foundation
@testable import DeskMat

struct SkyGradientTests {

    private func date(hour: Int, minute: Int = 0) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
    }

    // MARK: - nightFactor

    @Test func nightFactorIsHighAtMidnight() {
        #expect(SkyGradient.nightFactor(for: date(hour: 0), weatherCode: 0) > 0.9)
    }

    @Test func nightFactorIsHighAtLateNight() {
        #expect(SkyGradient.nightFactor(for: date(hour: 23), weatherCode: 0) > 0.9)
    }

    @Test func nightFactorIsZeroAtNoon() {
        #expect(SkyGradient.nightFactor(for: date(hour: 12), weatherCode: 0) == 0.0)
    }

    @Test func nightFactorIsZeroAtMidMorning() {
        #expect(SkyGradient.nightFactor(for: date(hour: 10), weatherCode: 0) == 0.0)
    }

    @Test func nightFactorIsAlwaysInUnitRange() {
        for hour in 0..<24 {
            let f = SkyGradient.nightFactor(for: date(hour: hour), weatherCode: 0)
            #expect(f >= 0.0, "night factor below 0 at hour \(hour)")
            #expect(f <= 1.0, "night factor above 1 at hour \(hour)")
        }
    }

    @Test func nightFactorIsInUnitRangeForAllWeatherCodes() {
        let codes = [0, 1, 2, 3, 45, 51, 61, 71, 80, 95, 99]
        for code in codes {
            let f = SkyGradient.nightFactor(for: date(hour: 0), weatherCode: code)
            #expect(f >= 0.0, "code \(code)")
            #expect(f <= 1.0, "code \(code)")
        }
    }

    // MARK: - color

    @Test func colorDoesNotCrashForAnyHour() {
        for hour in 0..<24 {
            _ = SkyGradient.color(for: date(hour: hour), weatherCode: 0)
        }
    }

    @Test func colorDoesNotCrashForAllWeatherCodes() {
        let codes = [0, 1, 2, 3, 45, 48, 51, 53, 55, 61, 63, 65, 71, 73, 75, 80, 81, 82, 95, 96, 99]
        for code in codes {
            _ = SkyGradient.color(for: date(hour: 12), weatherCode: code)
        }
    }

    // MARK: - borderColor

    @Test func borderColorDoesNotCrashForAnyHour() {
        for hour in 0..<24 {
            _ = SkyGradient.borderColor(for: date(hour: hour), weatherCode: 0)
        }
    }

    // MARK: - Gradient continuity

    @Test func nightFactorTransitionsThroughDawnAndDusk() {
        // Night factor should be high before dawn and low after sunrise
        let preDawn  = SkyGradient.nightFactor(for: date(hour: 4),  weatherCode: 0)
        let morning  = SkyGradient.nightFactor(for: date(hour: 9),  weatherCode: 0)
        #expect(preDawn > morning)
    }

    @Test func nightFactorTransitionsThroughDusk() {
        let afternoon = SkyGradient.nightFactor(for: date(hour: 15), weatherCode: 0)
        let lateNight = SkyGradient.nightFactor(for: date(hour: 22), weatherCode: 0)
        #expect(lateNight > afternoon)
    }
}
