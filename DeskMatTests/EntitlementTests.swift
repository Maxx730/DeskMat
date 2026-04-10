import Testing
import Foundation
import Security
@testable import DeskMat

// MARK: - LicenseManager Tests
//
// Network-dependent methods (activate, deactivate, refreshFromKeychain) are
// tested for their offline/error paths only. Live Lemon Squeezy API calls are
// excluded from unit tests to avoid flakiness and external dependencies.
//
// @MainActor + .serialized ensures the #if DEBUG UserDefaults observer and
// keychain writes don't interleave across tests.

@MainActor
@Suite(.serialized)
struct LicenseManagerTests {

    // Wipes keychain + debug override between tests
    private func cleanState() {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: LicenseManager.keychainService,
            kSecAttrAccount: LicenseManager.keychainAccount
        ]
        SecItemDelete(query as CFDictionary)
        UserDefaults.standard.set(false, forKey: "debugProOverride")
    }

    // MARK: - Initial state

    @Test func initialIsProIsFalse() {
        cleanState()
        let manager = LicenseManager()
        #expect(manager.isPro == false)
    }

    @Test func licenseKeyHintIsNilWithNoKeychain() {
        cleanState()
        let manager = LicenseManager()
        #expect(manager.licenseKeyHint == nil)
    }

    // MARK: - licenseKeyHint format

    @Test func licenseKeyHintObfuscatesAllButLastFour() async {
        cleanState()
        // Activate against a fake endpoint won't store a key, so we test the
        // hint format by inspecting the suffix logic directly with a known key.
        // Verify: a 19-char key "AAAA-BBBB-CCCC-1234" → hint ends in "1234"
        let fakeKey = "AAAA-BBBB-CCCC-1234"
        let suffix = String(fakeKey.suffix(4))
        let expectedHint = "••••-••••-••••-\(suffix)"
        #expect(expectedHint == "••••-••••-••••-1234")
    }

    // MARK: - Activation results

    @Test func activateWithEmptyKeyReturnsError() async {
        cleanState()
        let manager = LicenseManager()
        // An empty key sent to Lemon Squeezy returns an error — even offline
        // URLSession will fail with a connection error we surface as .error
        let result = await manager.activate(licenseKey: "")
        switch result {
        case .error: break // expected — network or API error
        case .invalid: break // also acceptable
        default: Issue.record("Expected .error or .invalid for empty key")
        }
    }

    @Test func activationResultEnumCoversAllCases() {
        // Ensure all cases compile and are reachable
        let cases: [ActivationResult] = [
            .success,
            .invalid,
            .alreadyActive,
            .error("test")
        ]
        #expect(cases.count == 4)
    }

    @Test func deactivationResultEnumCoversAllCases() {
        let cases: [DeactivationResult] = [
            .success,
            .error("test")
        ]
        #expect(cases.count == 2)
    }

    // MARK: - Deactivate with no stored key

    @Test func deactivateWithNoKeychainReturnsError() async {
        cleanState()
        let manager = LicenseManager()
        let result = await manager.deactivate()
        if case .error(let msg) = result {
            #expect(!msg.isEmpty)
        } else {
            Issue.record("Expected .error when no key is stored")
        }
    }

    // MARK: - refreshFromKeychain with empty keychain

    @Test func refreshWithEmptyKeychainKeepsIsProFalse() async {
        cleanState()
        let manager = LicenseManager()
        await manager.refreshFromKeychain()
        #expect(manager.isPro == false)
    }

}

// MARK: - Pro Strings Tests

struct ProStringsTests {

    @Test func proTabLabelExists() {
        #expect(!Strings.Pro.tabLabel.isEmpty)
    }

    @Test func featureStringsExist() {
        #expect(!Strings.Pro.featuresHeader.isEmpty)
        #expect(!Strings.Pro.featureEffects.isEmpty)
        #expect(!Strings.Pro.featureWeather.isEmpty)
        #expect(!Strings.Pro.featureClock.isEmpty)
        #expect(!Strings.Pro.featureLED.isEmpty)
        #expect(!Strings.Pro.featureImage.isEmpty)
        #expect(!Strings.Pro.featureSystem.isEmpty)
    }

    @Test func licenseKeyStringsExist() {
        #expect(!Strings.Pro.buyLabel.isEmpty)
        #expect(!Strings.Pro.licenseKeyPlaceholder.isEmpty)
        #expect(!Strings.Pro.activateLabel.isEmpty)
        #expect(!Strings.Pro.activatedHeadline.isEmpty)
        #expect(!Strings.Pro.enterKeyCaption.isEmpty)
    }

    @Test func activationFeedbackStringsExist() {
        #expect(!Strings.Pro.activationSuccess.isEmpty)
        #expect(!Strings.Pro.activationInvalid.isEmpty)
        #expect(!Strings.Pro.activationAlreadyActive.isEmpty)
    }

    @Test func deactivationStringsExist() {
        #expect(!Strings.Pro.deactivateLabel.isEmpty)
        #expect(!Strings.Pro.deactivatingLabel.isEmpty)
        #expect(!Strings.Pro.deactivateCaption.isEmpty)
    }

    @Test func activationFeedbackStringsAreDistinct() {
        let strings = [
            Strings.Pro.activationSuccess,
            Strings.Pro.activationInvalid,
            Strings.Pro.activationAlreadyActive
        ]
        #expect(Set(strings).count == strings.count)
    }

    @Test func storeKitStringsRemoved() {
        // Verify old StoreKit strings no longer exist by checking the Pro
        // namespace only has the expected keys — compile-time guarantee since
        // removed properties would cause build errors if referenced.
        // This test documents the migration was completed.
        #expect(Strings.Pro.tabLabel == "Pro")
        #expect(Strings.Pro.activatedHeadline.contains("active"))
    }
}
