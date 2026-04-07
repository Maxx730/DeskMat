import Testing
import Foundation
@testable import DeskMat

// MARK: - EntitlementManager Tests
//
// @MainActor ensures synchronous test bodies run atomically on the main thread.
// This prevents the #if DEBUG UserDefaults.didChangeNotification observer
// (delivered on .main via DispatchQueue.main.async) from firing mid-test and
// re-writing cachedIsPro while we are asserting. Without @MainActor, tests that
// remove the key can have it re-added by a queued observer callback before the
// #expect runs. cleanState() also clears debugProOverride, which when true
// causes the observer to call grantPro() on any UserDefaults change.

@MainActor
@Suite(.serialized)
struct EntitlementManagerTests {

    private func cleanState() {
        UserDefaults.standard.removeObject(forKey: "cachedIsPro")
        UserDefaults.standard.set(false, forKey: "debugProOverride")
    }

    @Test func initialIsProIsFalse() {
        cleanState()
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

    // MARK: - grantPro

    @Test func grantPro_setsIsProTrue() {
        cleanState()
        let manager = EntitlementManager()
        manager.grantPro()
        #expect(manager.isPro == true)
        cleanState()
    }

    @Test func grantPro_writesUserDefaultsKey() {
        let manager = EntitlementManager()
        // Remove then immediately write in the same synchronous block so no
        // queued observer callback can fire between setup and assertion.
        manager.clearProCache()
        manager.grantPro()
        #expect(UserDefaults.standard.bool(forKey: "cachedIsPro") == true)
        cleanState()
    }

    @Test func grantPro_isIdempotent() {
        let manager = EntitlementManager()
        manager.clearProCache()
        manager.grantPro()
        manager.grantPro()
        #expect(manager.isPro == true)
        #expect(UserDefaults.standard.bool(forKey: "cachedIsPro") == true)
        cleanState()
    }

    // MARK: - clearProCache

    @Test func clearProCache_removesUserDefaultsKey() {
        cleanState()
        UserDefaults.standard.set(true, forKey: "cachedIsPro")
        let manager = EntitlementManager()
        manager.clearProCache()
        #expect(UserDefaults.standard.object(forKey: "cachedIsPro") == nil)
    }

    @Test func clearProCache_safeWhenKeyAbsent() {
        cleanState()
        let manager = EntitlementManager()
        manager.clearProCache()
        #expect(UserDefaults.standard.object(forKey: "cachedIsPro") == nil)
    }

    // MARK: - UserDefaults seeding

    @Test func isPro_seededTrueFromUserDefaults() {
        // Grant pro first so the key is definitely written before we create a
        // second manager to test the seeding. Using grantPro() rather than a
        // raw UserDefaults write keeps setup and assertion in the same block.
        let writer = EntitlementManager()
        writer.clearProCache()
        writer.grantPro()
        let reader = EntitlementManager()
        #expect(reader.isPro == true)
        cleanState()
    }

    @Test func isPro_seededFalseWhenKeyAbsent() {
        cleanState()
        let manager = EntitlementManager()
        #expect(manager.isPro == false)
    }

    // MARK: - Pro tab string selection

    @Test func proTab_headlineIsLockedWhenNotPro() {
        cleanState()
        let manager = EntitlementManager()
        let headline = manager.isPro ? Strings.Pro.headlineUnlocked : Strings.Pro.headlineLocked
        #expect(headline == Strings.Pro.headlineLocked)
    }

    @Test func proTab_headlineIsUnlockedWhenPro() {
        cleanState()
        let manager = EntitlementManager()
        manager.grantPro()
        let headline = manager.isPro ? Strings.Pro.headlineUnlocked : Strings.Pro.headlineLocked
        #expect(headline == Strings.Pro.headlineUnlocked)
        cleanState()
    }

    @Test func proTab_ctaFallsBackWhenProductNil() {
        let manager = EntitlementManager()
        let cta = manager.product.map { Strings.Pro.unlockCTAWithPrice($0.displayPrice) } ?? Strings.Pro.unlockCTA
        #expect(cta == Strings.Pro.unlockCTA)
    }
}
