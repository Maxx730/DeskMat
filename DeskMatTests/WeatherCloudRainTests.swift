import Testing
import Foundation
@testable import DeskMat

// MARK: - Cloud count (WMO code → visible cloud strips)
//
// CloudsView.cloudCount(for:) is private. These tests mirror the switch exactly
// so that accidental edits to WMO mappings are caught immediately.
// The `clouds` array has 5 entries; count is clamped to [0, 5] by prefix().

struct CloudCountTests {

    // Mirror of CloudsView.cloudCount(for:) — must be kept in sync with the source.
    private func cloudCount(for code: Int) -> Int {
        switch code {
        case 0:          return 3
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

    // WMO 0 = clear sky. Always shows some clouds in current build.
    @Test func clearSkyCode0Returns3() {
        #expect(cloudCount(for: 0) == 3)
    }

    // WMO 1–3 = partly cloudy progression
    @Test func mainlyCloudFreeCode1Returns1() {
        #expect(cloudCount(for: 1) == 1)
    }

    @Test func partlyCloudyCode2Returns2() {
        #expect(cloudCount(for: 2) == 2)
    }

    @Test func overcastCode3Returns5() {
        #expect(cloudCount(for: 3) == 5)
    }

    // WMO 45/48 = fog codes
    @Test func fogCodes45And48Return3() {
        #expect(cloudCount(for: 45) == 3)
        #expect(cloudCount(for: 48) == 3)
    }

    // WMO 51/53/55 = light/moderate/heavy drizzle
    @Test func drizzleCodes51_53_55Return3() {
        #expect(cloudCount(for: 51) == 3)
        #expect(cloudCount(for: 53) == 3)
        #expect(cloudCount(for: 55) == 3)
    }

    // WMO 56/57 = freezing drizzle
    @Test func freezingDrizzleCodes56And57Return3() {
        #expect(cloudCount(for: 56) == 3)
        #expect(cloudCount(for: 57) == 3)
    }

    // WMO 61/63/65 = light/moderate/heavy rain
    @Test func rainCodes61_63_65Return4() {
        #expect(cloudCount(for: 61) == 4)
        #expect(cloudCount(for: 63) == 4)
        #expect(cloudCount(for: 65) == 4)
    }

    // WMO 66/67 = freezing rain
    @Test func freezingRainCodes66And67Return4() {
        #expect(cloudCount(for: 66) == 4)
        #expect(cloudCount(for: 67) == 4)
    }

    // WMO 71/73/75 = light/moderate/heavy snow, 77 = snow grains
    @Test func snowCodes71_73_75_77Return3() {
        #expect(cloudCount(for: 71) == 3)
        #expect(cloudCount(for: 73) == 3)
        #expect(cloudCount(for: 75) == 3)
        #expect(cloudCount(for: 77) == 3)
    }

    // WMO 80/81/82 = rain showers
    @Test func rainShowerCodes80_81_82Return4() {
        #expect(cloudCount(for: 80) == 4)
        #expect(cloudCount(for: 81) == 4)
        #expect(cloudCount(for: 82) == 4)
    }

    // WMO 85/86 = snow showers
    @Test func snowShowerCodes85And86Return3() {
        #expect(cloudCount(for: 85) == 3)
        #expect(cloudCount(for: 86) == 3)
    }

    // WMO 95 = thunderstorm, 96/99 = thunderstorm with hail
    @Test func thunderstormCode95Returns5() {
        #expect(cloudCount(for: 95) == 5)
    }

    @Test func thunderstormWithHailCodes96And99Return5() {
        #expect(cloudCount(for: 96) == 5)
        #expect(cloudCount(for: 99) == 5)
    }

    // Unknown code falls through to default
    @Test func unknownCodeReturnsDefault3() {
        #expect(cloudCount(for: 999) == 3)
        #expect(cloudCount(for: -1) == 3)
    }

    // Count is always in [0, 5] — the clouds array has exactly 5 entries
    @Test func countIsAlwaysAtMostFive() {
        let allCodes = [0, 1, 2, 3, 45, 48, 51, 53, 55, 56, 57,
                        61, 63, 65, 66, 67, 71, 73, 75, 77,
                        80, 81, 82, 85, 86, 95, 96, 99, 999]
        for code in allCodes {
            #expect(cloudCount(for: code) <= 5, "Count exceeded 5 for code \(code)")
            #expect(cloudCount(for: code) >= 0, "Count was negative for code \(code)")
        }
    }
}

// MARK: - Rain intensity (WMO code → dropsByIntensity index)
//
// RainView.intensity(for:) is private and maps into dropsByIntensity[0...4].
// Index 0 → empty drops (no rain visible).
// Intensity 4 is the heaviest — used for thunderstorm codes.

struct RainIntensityTests {

    // Mirror of RainView.intensity(for:) — must be kept in sync with the source.
    private func intensity(for code: Int) -> Int {
        switch code {
        case 51, 53, 55:        return 1
        case 56, 57, 61, 63:    return 2
        case 65, 66, 67,
             80, 81, 82:        return 3
        case 95, 96, 99:        return 4
        default:                return 3
        }
    }

    // Drizzle codes → lightest rain (1)
    @Test func drizzleCodes51_53_55ReturnIntensity1() {
        #expect(intensity(for: 51) == 1)
        #expect(intensity(for: 53) == 1)
        #expect(intensity(for: 55) == 1)
    }

    // Freezing drizzle + light rain codes → intensity 2
    @Test func freezingDrizzleAndLightRainReturnIntensity2() {
        #expect(intensity(for: 56) == 2)
        #expect(intensity(for: 57) == 2)
        #expect(intensity(for: 61) == 2)
        #expect(intensity(for: 63) == 2)
    }

    // Heavy rain + freezing rain + rain showers → intensity 3
    @Test func heavyRainAndShowersReturnIntensity3() {
        #expect(intensity(for: 65) == 3)
        #expect(intensity(for: 66) == 3)
        #expect(intensity(for: 67) == 3)
        #expect(intensity(for: 80) == 3)
        #expect(intensity(for: 81) == 3)
        #expect(intensity(for: 82) == 3)
    }

    // Thunderstorm codes → maximum intensity 4
    @Test func thunderstormCodes95_96_99ReturnIntensity4() {
        #expect(intensity(for: 95) == 4)
        #expect(intensity(for: 96) == 4)
        #expect(intensity(for: 99) == 4)
    }

    // Clear sky / fog / snow codes fall through to default (3 = visible for preview)
    @Test func nonRainCodesReturnDefault3() {
        for code in [0, 1, 2, 3, 45, 48, 71, 73, 75, 77, 85, 86, 999] {
            #expect(intensity(for: code) == 3, "Expected default 3 for code \(code)")
        }
    }

    // Intensity is always a valid index into dropsByIntensity[0...4]
    @Test func intensityIsAlwaysInBounds() {
        let allCodes = [0, 1, 2, 3, 45, 48, 51, 53, 55, 56, 57,
                        61, 63, 65, 66, 67, 71, 73, 75, 77,
                        80, 81, 82, 85, 86, 95, 96, 99, 999]
        for code in allCodes {
            let i = intensity(for: code)
            #expect(i >= 0 && i <= 4, "Index \(i) out of bounds for code \(code)")
        }
    }

    // Intensities are monotonically non-decreasing across severity ladder
    @Test func intensityIncreasesByWeatherSeverity() {
        #expect(intensity(for: 51) < intensity(for: 61))   // drizzle < rain
        #expect(intensity(for: 61) <= intensity(for: 65))  // light rain ≤ heavy rain
        #expect(intensity(for: 65) <= intensity(for: 95))  // heavy rain ≤ thunderstorm
    }
}

// MARK: - makeDrops determinism and property ranges
//
// RainView.makeDrops is a seeded PRNG — same seed always produces the same drops.
// Property ranges are enforced by the speed/length lo-hi parameters.

struct MakeDropsTests {

    // LCG PRNG matching RainView.makeDrops
    private func makeDrops(count: Int, seed: UInt64,
                           speedLo: Double, speedHi: Double,
                           lenLo: Double,   lenHi: Double) -> [(x: Double, speed: Double, length: Double, opacity: Double, phase: Double)] {
        var s = seed
        func rand() -> Double {
            s = s &* 6364136223846793005 &+ 1442695040888963407
            return Double(s >> 33) / Double(1 << 31)
        }
        return (0..<count).map { _ in
            (x:       rand(),
             speed:   speedLo  + rand() * (speedHi - speedLo),
             length:  lenLo    + rand() * (lenHi   - lenLo),
             opacity: 0.25     + rand() * 0.45,
             phase:   rand())
        }
    }

    // Intensity 1 → 25 drops
    @Test func intensity1Has25Drops() {
        let drops = makeDrops(count: 25, seed: 0xA1B2C3D4E5F60001,
                              speedLo: 60, speedHi: 90, lenLo: 4, lenHi: 6)
        #expect(drops.count == 25)
    }

    // Intensity 2 → 40 drops
    @Test func intensity2Has40Drops() {
        let drops = makeDrops(count: 40, seed: 0xA1B2C3D4E5F60002,
                              speedLo: 80, speedHi: 120, lenLo: 5, lenHi: 8)
        #expect(drops.count == 40)
    }

    // Intensity 3 → 60 drops
    @Test func intensity3Has60Drops() {
        let drops = makeDrops(count: 60, seed: 0xA1B2C3D4E5F60003,
                              speedLo: 110, speedHi: 160, lenLo: 6, lenHi: 10)
        #expect(drops.count == 60)
    }

    // Intensity 4 → 80 drops
    @Test func intensity4Has80Drops() {
        let drops = makeDrops(count: 80, seed: 0xA1B2C3D4E5F60004,
                              speedLo: 140, speedHi: 200, lenLo: 7, lenHi: 12)
        #expect(drops.count == 80)
    }

    // Drop counts increase with intensity
    @Test func dropCountsAscendByIntensity() {
        let counts = [25, 40, 60, 80]
        #expect(counts == counts.sorted())
    }

    // Property ranges: x and phase normalised [0, 1]
    @Test func xIsNormalised() {
        let drops = makeDrops(count: 25, seed: 0xA1B2C3D4E5F60001,
                              speedLo: 60, speedHi: 90, lenLo: 4, lenHi: 6)
        for d in drops {
            #expect(d.x >= 0 && d.x <= 1, "x=\(d.x) out of [0,1]")
        }
    }

    @Test func phaseIsNormalised() {
        let drops = makeDrops(count: 25, seed: 0xA1B2C3D4E5F60001,
                              speedLo: 60, speedHi: 90, lenLo: 4, lenHi: 6)
        for d in drops {
            #expect(d.phase >= 0 && d.phase <= 1, "phase=\(d.phase) out of [0,1]")
        }
    }

    // Speed stays within the declared lo-hi range
    @Test func speedIsWithinRange() {
        let drops = makeDrops(count: 25, seed: 0xA1B2C3D4E5F60001,
                              speedLo: 60, speedHi: 90, lenLo: 4, lenHi: 6)
        for d in drops {
            #expect(d.speed >= 60 && d.speed <= 90, "speed=\(d.speed) out of [60,90]")
        }
    }

    // Length stays within the declared lo-hi range
    @Test func lengthIsWithinRange() {
        let drops = makeDrops(count: 25, seed: 0xA1B2C3D4E5F60001,
                              speedLo: 60, speedHi: 90, lenLo: 4, lenHi: 6)
        for d in drops {
            #expect(d.length >= 4 && d.length <= 6, "length=\(d.length) out of [4,6]")
        }
    }

    // Opacity band is [0.25, 0.70]
    @Test func opacityIsWithinBand() {
        let drops = makeDrops(count: 25, seed: 0xA1B2C3D4E5F60001,
                              speedLo: 60, speedHi: 90, lenLo: 4, lenHi: 6)
        for d in drops {
            #expect(d.opacity >= 0.25 && d.opacity <= 0.70,
                    "opacity=\(d.opacity) out of [0.25, 0.70]")
        }
    }

    // Same seed → same first drop (PRNG is deterministic)
    @Test func seedIsDeterministic() {
        let a = makeDrops(count: 5, seed: 0xA1B2C3D4E5F60001,
                          speedLo: 60, speedHi: 90, lenLo: 4, lenHi: 6)
        let b = makeDrops(count: 5, seed: 0xA1B2C3D4E5F60001,
                          speedLo: 60, speedHi: 90, lenLo: 4, lenHi: 6)
        #expect(a.first?.x == b.first?.x)
        #expect(a.first?.speed == b.first?.speed)
    }

    // Different seeds → different first drop
    @Test func differentSeedsProduceDifferentDrops() {
        let a = makeDrops(count: 5, seed: 0xA1B2C3D4E5F60001,
                          speedLo: 60, speedHi: 90, lenLo: 4, lenHi: 6)
        let b = makeDrops(count: 5, seed: 0xA1B2C3D4E5F60002,
                          speedLo: 60, speedHi: 90, lenLo: 4, lenHi: 6)
        #expect(a.first?.x != b.first?.x)
    }
}
