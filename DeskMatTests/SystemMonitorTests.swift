import Testing
import Foundation
@testable import DeskMat

// MARK: - SystemMonitorService Tests

struct SystemMonitorServiceTests {

    @Test func initialValuesAreZero() {
        let monitor = SystemMonitorService()
        #expect(monitor.cpuPercent == 0)
        #expect(monitor.ramUsedGB == 0)
        #expect(monitor.netInKBs == 0)
        #expect(monitor.netOutKBs == 0)
    }

    @Test func ramTotalGBIsPositive() {
        let monitor = SystemMonitorService()
        #expect(monitor.ramTotalGB > 0)
    }

    @Test func ramTotalGBMatchesProcessInfo() {
        let monitor = SystemMonitorService()
        let expected = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
        #expect(abs(monitor.ramTotalGB - expected) < 0.001)
    }

    @Test func startAndStopDoNotCrash() {
        let monitor = SystemMonitorService()
        monitor.start()
        monitor.stop()
        monitor.stop()
    }

    @Test func startIsIdempotent() {
        let monitor = SystemMonitorService()
        monitor.start()
        monitor.start()
        monitor.stop()
    }

    @Test func cpuPercentIsBetweenZeroAndOne() async throws {
        let monitor = SystemMonitorService()
        monitor.start()
        try await Task.sleep(for: .seconds(2.1))
        monitor.stop()
        #expect(monitor.cpuPercent >= 0)
        #expect(monitor.cpuPercent <= 1)
    }

    @Test func ramUsedGBIsPositiveAfterPoll() async throws {
        let monitor = SystemMonitorService()
        monitor.start()
        try await Task.sleep(for: .seconds(1.1))
        monitor.stop()
        #expect(monitor.ramUsedGB > 0)
    }

    @Test func ramUsedGBDoesNotExceedTotal() async throws {
        let monitor = SystemMonitorService()
        monitor.start()
        try await Task.sleep(for: .seconds(1.1))
        monitor.stop()
        #expect(monitor.ramUsedGB <= monitor.ramTotalGB)
    }
}

// MARK: - Network Formatter Logic Tests

struct NetworkFormatterTests {

    // Mirrors the private `formatted` computed property in NetRow.
    private func formatted(value: Double) -> (value: String, unit: String) {
        value >= 1024
            ? (String(format: "%.1f", value / 1024), "MB/s")
            : (String(format: "%.1f", value),         "KB/s")
    }

    @Test func belowThresholdShowsKBs() {
        let result = formatted(value: 500)
        #expect(result.unit == "KB/s")
        #expect(result.value == "500.0")
    }

    @Test func atThresholdShowsMBs() {
        let result = formatted(value: 1024)
        #expect(result.unit == "MB/s")
        #expect(result.value == "1.0")
    }

    @Test func aboveThresholdShowsMBs() {
        let result = formatted(value: 2048)
        #expect(result.unit == "MB/s")
        #expect(result.value == "2.0")
    }

    @Test func zeroShowsKBs() {
        let result = formatted(value: 0)
        #expect(result.unit == "KB/s")
        #expect(result.value == "0.0")
    }

    @Test func justBelowThresholdShowsKBs() {
        let result = formatted(value: 1023.9)
        #expect(result.unit == "KB/s")
    }

    @Test func largeValueFormatsCorrectly() {
        let result = formatted(value: 10240)
        #expect(result.unit == "MB/s")
        #expect(result.value == "10.0")
    }
}
