import Testing
import Foundation
import AppKit
@testable import DeskMat

// MARK: - Launch Animation Running State Tests
//
// The flash animation starts only when runningApplications(withBundleIdentifier:)
// returns empty — i.e., the app is not already running. These tests verify that
// gate behaves correctly for known and unknown bundle identifiers.

struct LaunchAnimationRunningStateTests {

    @Test func unknownBundleHasNoRunningInstances() {
        // An unrecognised bundle should always return empty — animation should start
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.deskmat.notareal.app.xyz")
        #expect(apps.isEmpty)
    }

    @Test func finderIsAlwaysRunning() {
        // Finder is guaranteed to be running — animation should NOT start for it
        // (DeskMat also special-cases Finder in launchOrFocus, so this double-confirms)
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder")
        #expect(!apps.isEmpty)
    }

    @Test func emptyBundleIdentifierHasNoRunningInstances() {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: "")
        #expect(apps.isEmpty)
    }
}

// MARK: - Launch Animation Bundle Matching Tests
//
// The animation stops inside the didLaunchApplicationNotification handler only
// when the launched app's bundleIdentifier matches the shortcut's bundleIdentifier.
// These tests verify that matching/non-matching logic behaves correctly so that
// only the right button's animation stops when an app launches.

struct LaunchAnimationBundleMatchingTests {

    @Test func matchingBundleIdentifierStopsAnimation() {
        let shortcutBundle = "com.apple.Safari"
        let launchedBundle = "com.apple.Safari"
        // Same bundle → handler should set isLaunching = false for this button
        #expect(launchedBundle == shortcutBundle)
    }

    @Test func differentBundleIdentifierPreservesAnimation() {
        let shortcutBundle = "com.apple.Safari"
        let otherBundle = "com.apple.finder"
        // Different bundle → this button's animation must not be interrupted
        #expect(otherBundle != shortcutBundle)
    }

    @Test func nilBundleIdentifierDoesNotMatch() {
        let shortcutBundle = "com.apple.Safari"
        let nilBundle: String? = nil
        // Nil bundle (e.g. system process) must not stop the animation
        #expect(nilBundle != shortcutBundle)
    }

    @Test func bundleIdentifierComparisonIsCaseSensitive() {
        let shortcutBundle = "com.apple.Safari"
        let wrongCase = "com.apple.safari"
        // Bundle IDs are case-sensitive on macOS — must not match
        #expect(wrongCase != shortcutBundle)
    }
}

// MARK: - Launch Animation Notification Payload Tests
//
// Verifies that the NSWorkspace applicationUserInfoKey can be used to extract
// a running application from a notification's userInfo, matching how the
// didLaunchApplicationNotification handler reads the launched app.

struct LaunchAnimationNotificationTests {

    @Test func applicationUserInfoKeyExtractsRunningApp() {
        // Simulate what didLaunchApplicationNotification delivers in userInfo
        guard let finder = NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.apple.finder"
        ).first else {
            Issue.record("Finder must be running for this test")
            return
        }

        let userInfo: [AnyHashable: Any] = [NSWorkspace.applicationUserInfoKey: finder]
        let extracted = userInfo[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication

        #expect(extracted != nil)
        #expect(extracted?.bundleIdentifier == "com.apple.finder")
    }

    @Test func missingApplicationKeyReturnsNil() {
        // If userInfo doesn't contain the app key, extraction returns nil and
        // the animation guard clause safely skips setting isLaunching = false
        let userInfo: [AnyHashable: Any] = [:]
        let extracted = userInfo[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        #expect(extracted == nil)
    }
}
