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

    @Test func historyArraysAreEmptyInitially() {
        let monitor = SystemMonitorService()
        #expect(monitor.cpuHistory.isEmpty)
        #expect(monitor.netInHistory.isEmpty)
        #expect(monitor.netOutHistory.isEmpty)
    }

    @Test func cpuHistoryGrowsAfterPolling() async throws {
        let monitor = SystemMonitorService()
        monitor.start()
        try await Task.sleep(for: .seconds(1.0))
        monitor.stop()
        #expect(!monitor.cpuHistory.isEmpty)
    }

    @Test func cpuHistoryValuesAreNormalised() async throws {
        let monitor = SystemMonitorService()
        monitor.start()
        try await Task.sleep(for: .seconds(1.0))
        monitor.stop()
        for v in monitor.cpuHistory {
            #expect(v >= 0.0)
            #expect(v <= 1.0)
        }
    }

    @Test func cpuHistoryDoesNotExceedCapacity() async throws {
        let monitor = SystemMonitorService()
        monitor.start()
        try await Task.sleep(for: .seconds(10.0))
        monitor.stop()
        #expect(monitor.cpuHistory.count <= 30)
    }

    @Test func netHistoryGrowsAfterPolling() async throws {
        let monitor = SystemMonitorService()
        monitor.start()
        try await Task.sleep(for: .seconds(1.0))
        monitor.stop()
        #expect(!monitor.netInHistory.isEmpty)
        #expect(!monitor.netOutHistory.isEmpty)
    }

    @Test func netHistoryValuesAreNonNegative() async throws {
        let monitor = SystemMonitorService()
        monitor.start()
        try await Task.sleep(for: .seconds(1.0))
        monitor.stop()
        for v in monitor.netInHistory  { #expect(v >= 0) }
        for v in monitor.netOutHistory { #expect(v >= 0) }
    }

    @Test func netHistoryDoesNotExceedCapacity() async throws {
        let monitor = SystemMonitorService()
        monitor.start()
        try await Task.sleep(for: .seconds(20.0))
        monitor.stop()
        #expect(monitor.netInHistory.count  <= 60)
        #expect(monitor.netOutHistory.count <= 60)
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

    // Mirrors NetPanelView.formattedRate: whole-number KB/s, one-decimal MB/s, unit embedded.
    private func formatted(value: Double) -> String {
        value >= 1024
            ? String(format: "%.1f MB/s", value / 1024)
            : "\(Int(value)) KB/s"
    }

    @Test func belowThresholdShowsKBs() {
        #expect(formatted(value: 500) == "500 KB/s")
    }

    @Test func atThresholdShowsMBs() {
        #expect(formatted(value: 1024) == "1.0 MB/s")
    }

    @Test func aboveThresholdShowsMBs() {
        #expect(formatted(value: 2048) == "2.0 MB/s")
    }

    @Test func zeroShowsKBs() {
        #expect(formatted(value: 0) == "0 KB/s")
    }

    @Test func justBelowThresholdShowsKBs() {
        #expect(formatted(value: 1023.9) == "1023 KB/s")
    }

    @Test func largeValueFormatsCorrectly() {
        #expect(formatted(value: 10240) == "10.0 MB/s")
    }

    @Test func fractionalKBsTruncatesToInt() {
        #expect(formatted(value: 99.9) == "99 KB/s")
    }
}
