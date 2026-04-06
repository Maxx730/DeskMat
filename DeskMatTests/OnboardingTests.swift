import Testing
import Foundation
@testable import DeskMat

// MARK: - Onboarding Flag Tests

@Suite(.serialized)
struct OnboardingFlagTests {

    private let key = "hasCompletedOnboarding"

    @Test func onboardingFlagDefaultsToFalse() {
        let defaults = UserDefaults.standard
        let existing = defaults.object(forKey: key)
        defer {
            if let existing { defaults.set(existing, forKey: key) }
            else { defaults.removeObject(forKey: key) }
        }

        defaults.removeObject(forKey: key)
        #expect(defaults.bool(forKey: key) == false)
    }

    @Test func onboardingFlagCanBeSetToTrue() {
        let defaults = UserDefaults.standard
        let existing = defaults.object(forKey: key)
        defer {
            if let existing { defaults.set(existing, forKey: key) }
            else { defaults.removeObject(forKey: key) }
        }

        defaults.set(true, forKey: key)
        #expect(defaults.bool(forKey: key) == true)
    }

    @Test func onboardingFlagCanBeCleared() {
        let defaults = UserDefaults.standard
        let existing = defaults.object(forKey: key)
        defer {
            if let existing { defaults.set(existing, forKey: key) }
            else { defaults.removeObject(forKey: key) }
        }

        defaults.set(true, forKey: key)
        defaults.removeObject(forKey: key)
        #expect(defaults.bool(forKey: key) == false)
    }
}
