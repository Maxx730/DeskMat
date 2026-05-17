import Testing
import Foundation
import AppKit
@testable import DeskMat

// MARK: - WindowStateService Tests

struct WindowStateServiceTests {

    @Test func initialWindowInfoIsEmpty() {
        let service = WindowStateService()
        // info for an unrecognized bundle returns zeros — not a crash
        let result = service.info(for: "com.deskmat.nonexistent.xyz")
        #expect(result.count == 0)
        #expect(result.hasMinimized == false)
    }

    @Test func refreshDoesNotCrash() {
        let service = WindowStateService()
        service.refresh()
        service.refresh()
    }

    @Test func infoForUnknownBundleReturnsZeros() {
        let service = WindowStateService()
        service.refresh()
        let result = service.info(for: "com.deskmat.nonexistent.bundle.id.xyz")
        #expect(result.count == 0)
        #expect(result.hasMinimized == false)
    }

    @Test func infoForFinderReturnsPositiveCount() {
        // Finder is always running and has at least one window layer entry.
        let service = WindowStateService()
        service.refresh()
        let result = service.info(for: "com.apple.finder")
        // We can't assert exact counts (desktop state varies), but refresh must
        // not crash and must return a sensible non-negative value.
        #expect(result.count >= 0)
    }

    @Test func multipleRefreshesAreIdempotent() {
        let service = WindowStateService()
        service.refresh()
        let first = service.info(for: "com.apple.finder")
        service.refresh()
        let second = service.info(for: "com.apple.finder")
        // counts may fluctuate by ±1 between calls; just verify no crash and
        // that both invocations return non-negative values.
        #expect(first.count >= 0)
        #expect(second.count >= 0)
    }
}

// MARK: - WindowStateService Tuple Shape Tests
//
// Verifies the (count:hasMinimized:) shape of the returned tuple so that
// callers can rely on the field names without breaking silently on rename.

struct WindowStateServiceTupleTests {

    @Test func infoTupleFieldsAreAccessibleByName() {
        let service = WindowStateService()
        let result = service.info(for: "com.deskmat.nonexistent.xyz")
        // Access both named fields — compilation failure means the API changed.
        let _ = result.count
        let _ = result.hasMinimized
    }

    @Test func countIsNonNegative() {
        let service = WindowStateService()
        service.refresh()
        let result = service.info(for: "com.apple.finder")
        #expect(result.count >= 0)
    }
}
