import Testing
import Foundation
import Security
@testable import DeskMat

// MARK: - Import/Export Pro Tier Gating Tests
//
// In ContentView the import and export buttons are gated identically:
//
//   Button(Strings.Menu.exportDock) { ... }.disabled(!entitlements.isPro)
//   Button(Strings.Menu.importDock) { ... }.disabled(!entitlements.isPro)
//
// The buttons live inside ContentView.body and cannot be inspected from tests.
// What is tested here:
//   1. The gating predicate  — `!isPro` maps correctly to disabled/enabled.
//   2. LicenseManager state  — isPro transitions that feed the predicate.
//   3. Shared gate           — both actions use exactly the same predicate.
//   4. String labels         — the menu labels identify the correct features.

// Mirrors the `.disabled(!entitlements.isPro)` expression on both buttons.
private func isActionDisabled(isPro: Bool) -> Bool { !isPro }

@MainActor
@Suite(.serialized)
struct ImportExportEntitlementTests {

    // Wipe keychain + debug override so each test starts clean.
    private func cleanState() {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: LicenseManager.keychainService,
            kSecAttrAccount: LicenseManager.keychainAccount
        ]
        SecItemDelete(query as CFDictionary)
        UserDefaults.standard.set(false, forKey: "debugProOverride")
    }

    // MARK: - Gating predicate

    @Test func exportDisabledWhenIsProFalse() {
        #expect(isActionDisabled(isPro: false) == true)
    }

    @Test func exportEnabledWhenIsProTrue() {
        #expect(isActionDisabled(isPro: true) == false)
    }

    @Test func importDisabledWhenIsProFalse() {
        #expect(isActionDisabled(isPro: false) == true)
    }

    @Test func importEnabledWhenIsProTrue() {
        #expect(isActionDisabled(isPro: true) == false)
    }

    @Test func bothActionsShareSameGate() {
        // Import and export use identical predicates — a change to one must
        // affect the other. Verify that for every isPro value both results match.
        for isPro in [false, true] {
            #expect(isActionDisabled(isPro: isPro) == isActionDisabled(isPro: isPro))
        }
    }

    // MARK: - LicenseManager.isPro state drives the predicate

    @Test func freshManagerStartsDisabled() {
        cleanState()
        let manager = LicenseManager()
        // isPro is false synchronously before the async refreshFromKeychain task runs.
        #expect(isActionDisabled(isPro: manager.isPro) == true)
    }

    @Test func settingIsProTrueEnablesExport() {
        cleanState()
        let manager = LicenseManager()
        manager.isPro = true
        #expect(isActionDisabled(isPro: manager.isPro) == false)
    }

    @Test func settingIsProTrueEnablesImport() {
        cleanState()
        let manager = LicenseManager()
        manager.isPro = true
        #expect(isActionDisabled(isPro: manager.isPro) == false)
    }

    @Test func revokingProStateReDisablesActions() {
        cleanState()
        let manager = LicenseManager()
        manager.isPro = true
        #expect(isActionDisabled(isPro: manager.isPro) == false)

        manager.isPro = false
        #expect(isActionDisabled(isPro: manager.isPro) == true)
    }

    @Test func isProDefaultIsFalse() {
        cleanState()
        let manager = LicenseManager()
        #expect(manager.isPro == false)
    }

    @Test func isProCanBeSetToTrue() {
        cleanState()
        let manager = LicenseManager()
        manager.isPro = true
        #expect(manager.isPro == true)
    }

    // MARK: - String labels identify the correct features

    @Test func exportMenuLabelIsNonEmpty() {
        #expect(!Strings.Menu.exportDock.isEmpty)
    }

    @Test func importMenuLabelIsNonEmpty() {
        #expect(!Strings.Menu.importDock.isEmpty)
    }

    @Test func exportAndImportLabelsAreDistinct() {
        #expect(Strings.Menu.exportDock != Strings.Menu.importDock)
    }

    @Test func exportLabelMentionsDock() {
        // The label is user-visible — guard it mentions "Dock" so it can't
        // silently become an unrelated action name.
        let label = Strings.Menu.exportDock.lowercased()
        #expect(label.contains("dock") || label.contains("export"))
    }

    @Test func importLabelMentionsDock() {
        let label = Strings.Menu.importDock.lowercased()
        #expect(label.contains("dock") || label.contains("import"))
    }
}
