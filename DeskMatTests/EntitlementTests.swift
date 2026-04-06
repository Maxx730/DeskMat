import Testing
import Foundation
@testable import DeskMat

// MARK: - EntitlementManager Tests

@Suite(.serialized)
struct EntitlementManagerTests {

    @Test func initialIsProIsFalse() {
        let manager = EntitlementManager()
        #expect(manager.isPro == false)
    }

    @Test func initialProductIsNil() {
        let manager = EntitlementManager()
        #expect(manager.product == nil)
    }

    @Test func productIDMatchesExpected() {
        #expect(EntitlementManager.productID == "com.deskmat.pro")
    }

    @Test func purchaseWithNilProductReturnsCancelled() async throws {
        let manager = EntitlementManager()
        let result = try await manager.purchase()
        if case .cancelled = result { } else { Issue.record("expected .cancelled when product is nil") }
    }

    @Test func isProCanBeSetToTrue() {
        let manager = EntitlementManager()
        manager.isPro = true
        #expect(manager.isPro == true)
    }

    @Test func isProCanBeSetBackToFalse() {
        let manager = EntitlementManager()
        manager.isPro = true
        manager.isPro = false
        #expect(manager.isPro == false)
    }
}
