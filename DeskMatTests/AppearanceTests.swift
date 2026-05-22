import Testing
import AppKit
@testable import DeskMat

// MARK: - Appearance Tests
//
// applyAppearance() reads UserDefaults and calls NSApp.appearance — the global
// NSApp.appearance side-effect is tested via the AppearanceMode→name mapping
// rather than inspecting NSApp.appearance directly (which would mutate global
// test state). The key invariant is that the three modes map to distinct, stable
// NSAppearance.Name values.

@MainActor
@Suite(.serialized)
struct AppearanceTests {

    // MARK: - applyAppearance reads UserDefaults

    @Test func applyAppearanceWithSystemModeResetsToNil() {
        UserDefaults.standard.set(AppearanceMode.system.rawValue, forKey: "appearanceMode")
        let delegate = AppDelegate()
        delegate.applyAppearance()
        #expect(NSApp.appearance == nil)
        UserDefaults.standard.removeObject(forKey: "appearanceMode")
    }

    @Test func applyAppearanceWithLightModeSelectsAqua() {
        UserDefaults.standard.set(AppearanceMode.light.rawValue, forKey: "appearanceMode")
        let delegate = AppDelegate()
        delegate.applyAppearance()
        #expect(NSApp.appearance?.name == .aqua)
        // Restore
        NSApp.appearance = nil
        UserDefaults.standard.removeObject(forKey: "appearanceMode")
    }

    @Test func applyAppearanceWithDarkModeSelectsDarkAqua() {
        UserDefaults.standard.set(AppearanceMode.dark.rawValue, forKey: "appearanceMode")
        let delegate = AppDelegate()
        delegate.applyAppearance()
        #expect(NSApp.appearance?.name == .darkAqua)
        // Restore
        NSApp.appearance = nil
        UserDefaults.standard.removeObject(forKey: "appearanceMode")
    }

    @Test func applyAppearanceDefaultsToSystemWhenKeyMissing() {
        UserDefaults.standard.removeObject(forKey: "appearanceMode")
        let delegate = AppDelegate()
        delegate.applyAppearance()
        #expect(NSApp.appearance == nil)
    }

    @Test func applyAppearanceDefaultsToSystemForUnknownRawValue() {
        UserDefaults.standard.set("bogus", forKey: "appearanceMode")
        let delegate = AppDelegate()
        delegate.applyAppearance()
        #expect(NSApp.appearance == nil)
        UserDefaults.standard.removeObject(forKey: "appearanceMode")
    }

    // MARK: - AppearanceMode enum contract

    @Test func allModesHaveUniqueRawValues() {
        let raws = AppearanceMode.allCases.map(\.rawValue)
        #expect(Set(raws).count == raws.count)
    }

    @Test func systemModeRawValue() {
        #expect(AppearanceMode.system.rawValue == "System")
    }

    @Test func lightModeRawValue() {
        #expect(AppearanceMode.light.rawValue == "Light")
    }

    @Test func darkModeRawValue() {
        #expect(AppearanceMode.dark.rawValue == "Dark")
    }

    @Test func lightAndDarkModesAreDistinct() {
        #expect(AppearanceMode.light != AppearanceMode.dark)
    }
}
