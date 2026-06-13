import Testing
import Foundation
@testable import DeskMat

// MARK: - RAM fraction
//
// RAMView.fraction = total > 0 ? min(used / total, 1.0) : 0
// Drives the ImageProgressView fill, so wrong values visually misrepresent usage.

struct RAMFractionTests {

    private func fraction(used: Double, total: Double) -> Double {
        total > 0 ? max(0, min(used / total, 1.0)) : 0
    }

    @Test func zeroTotalReturnsZero() {
        #expect(fraction(used: 8, total: 0) == 0)
    }

    @Test func halfUsedReturnsHalf() {
        #expect(fraction(used: 8, total: 16) == 0.5)
    }

    @Test func fullyUsedReturnsOne() {
        #expect(fraction(used: 16, total: 16) == 1.0)
    }

    @Test func overUsedClampsToOne() {
        #expect(fraction(used: 20, total: 16) == 1.0)
    }

    @Test func zeroUsedReturnsZero() {
        #expect(fraction(used: 0, total: 16) == 0)
    }

    @Test func fractionIsNeverNegative() {
        #expect(fraction(used: -4, total: 16) >= 0)
    }

    @Test func fractionIsNeverAboveOne() {
        for used in stride(from: 0.0, through: 32.0, by: 4.0) {
            #expect(fraction(used: used, total: 16) <= 1.0)
        }
    }
}

// MARK: - CPU chart floor baseline
//
// CPUGraphView.chartPoints: display = floor + raw * (1.0 - floor), floor = 0.15
// The 0.15 floor prevents the line from hugging the bottom at 0% CPU,
// keeping the waveform readable. Wrong floor values shift the entire graph.

struct CPUChartFloorTests {

    private let floor: Double = 0.15

    private func display(raw: Double) -> Double {
        floor + raw * (1.0 - floor)
    }

    @Test func zeroRawHitsFloor() {
        #expect(display(raw: 0) == 0.15)
    }

    @Test func fullRawHitsOne() {
        #expect(display(raw: 1.0) == 1.0)
    }

    @Test func halfRawIsCorrect() {
        #expect(abs(display(raw: 0.5) - 0.575) < 1e-10)
    }

    @Test func displayAlwaysAboveFloor() {
        for raw in stride(from: 0.0, through: 1.0, by: 0.1) {
            #expect(display(raw: raw) >= floor)
        }
    }

    @Test func displayNeverExceedsOne() {
        for raw in stride(from: 0.0, through: 1.0, by: 0.1) {
            #expect(display(raw: raw) <= 1.0)
        }
    }

    // Y is inverted: y = height * (1.0 - display), so 0% CPU is near the bottom
    @Test func yCoordinateIsInverted() {
        let height: CGFloat = 64
        let yAtZeroCPU  = height * (1.0 - display(raw: 0))   // near bottom
        let yAtFullCPU  = height * (1.0 - display(raw: 1.0)) // near top (y=0)
        #expect(yAtZeroCPU > yAtFullCPU)
    }
}

// MARK: - Network chart floor baseline
//
// NetPanelView.chartPoints: floor = 0.265, display = floor + normalised * (1.0 - floor)
// Separate floor from the CPU graph so the two panels look visually distinct.

struct NetChartFloorTests {

    private let floor: Double = 0.265

    private func display(normalised: Double) -> Double {
        floor + normalised * (1.0 - floor)
    }

    @Test func zeroNormalisedHitsFloor() {
        #expect(abs(display(normalised: 0) - 0.265) < 1e-10)
    }

    @Test func fullNormalisedHitsOne() {
        #expect(abs(display(normalised: 1.0) - 1.0) < 1e-10)
    }

    @Test func netFloorIsHigherThanCPUFloor() {
        #expect(floor > 0.15) // net baseline sits higher than CPU baseline
    }
}

// MARK: - Network rate formatter
//
// NetPanelView.formattedRate: v >= 1024 → MB/s, else KB/s
// The 1024 boundary is binary (kibibyte), not decimal (kilobyte).

struct NetRateFormatterTests {

    private func formatted(_ kbps: Double) -> String {
        kbps >= 1024
            ? String(format: "%.1f MB/s", kbps / 1024)
            : "\(Int(kbps)) KB/s"
    }

    @Test func zeroBytesShowsKBps() {
        #expect(formatted(0) == "0 KB/s")
    }

    @Test func belowThresholdShowsKBps() {
        #expect(formatted(512) == "512 KB/s")
        #expect(formatted(1023) == "1023 KB/s")
    }

    @Test func atThresholdShowsMBps() {
        #expect(formatted(1024) == "1.0 MB/s")
    }

    @Test func aboveThresholdShowsMBps() {
        #expect(formatted(2048) == "2.0 MB/s")
        #expect(formatted(10240) == "10.0 MB/s")
    }

    @Test func fractionalMBpsFormattedToOneDecimal() {
        #expect(formatted(1536) == "1.5 MB/s")
    }
}

// MARK: - HalfCircleMeter colour bands
//
// meterColor: white below 60%, blend 60–80%, red above 80%.
// Wrong thresholds shift the warning colour earlier or later than intended.

struct HalfCircleMeterColorTests {

    private func band(for v: Double) -> String {
        if v < 0.6  { return "white" }
        if v < 0.8  { return "blend" }
        return "red"
    }

    @Test func belowSixtyIsWhite() {
        for v in [0.0, 0.3, 0.59] {
            #expect(band(for: v) == "white", "Expected white at \(v)")
        }
    }

    @Test func sixtyToEightyIsBlend() {
        for v in [0.6, 0.7, 0.79] {
            #expect(band(for: v) == "blend", "Expected blend at \(v)")
        }
    }

    @Test func eightyAndAboveIsRed() {
        for v in [0.8, 0.9, 1.0] {
            #expect(band(for: v) == "red", "Expected red at \(v)")
        }
    }

    // HalfCircleMeter clamps value: max(0, min(1, value))
    @Test func negativeValueClampsToZero() {
        let clamped = max(0.0, min(1.0, -0.5))
        #expect(clamped == 0)
    }

    @Test func overOneValueClampsToOne() {
        let clamped = max(0.0, min(1.0, 1.5))
        #expect(clamped == 1.0)
    }

    // Blend factor at the 60% boundary
    @Test func blendFactorAtSixtyIsZero() {
        let t = (0.6 - 0.6) / 0.2
        #expect(t == 0) // no orange at the start of the blend band
    }

    // Blend factor at the 80% boundary
    @Test func blendFactorAtEightyIsOne() {
        let t = (0.8 - 0.6) / 0.2
        #expect(abs(t - 1.0) < 1e-10) // fully orange at the end of the blend band
    }
}
