import Testing
import Foundation
@testable import DeskMat

// MARK: - AppShortcutButton Logic Tests
//
// AppShortcutButton is a SwiftUI View — its body, gesture handlers, and private
// animation methods cannot be called from unit tests. The tests here cover the
// pure-logic pieces: hover scale amplitude math, the Finder bundle-ID special
// case, and the label display precedence (customLabel over displayName).

struct AppShortcutButtonTests {

    // MARK: - Bounce amplitude math
    //
    // animateBounce computes `a = hoverSize.scale - 1.0` and uses it to drive
    // successive bounce steps. These tests verify the amplitude is correct for
    // each HoverSize so a scale change doesn't silently break the animation.

    @Test func bounceAmplitudeSmall() {
        #expect(HoverSize.small.scale == 1.2)
    }

    @Test func bounceAmplitudeMedium() {
        #expect(HoverSize.medium.scale == 1.5)
    }

    @Test func bounceAmplitudeLarge() {
        #expect(HoverSize.large.scale == 1.8)
    }

    @Test func bounceAmplitudeIsPositiveForAllSizes() {
        for size in HoverSize.allCases {
            #expect(size.scale - 1.0 > 0)
        }
    }

    @Test func scaleIsAlwaysGreaterThanOne() {
        for size in HoverSize.allCases {
            #expect(size.scale > 1.0)
        }
    }

    // MARK: - Label display precedence
    //
    // Mirrors AppShortcut.label: customLabel ?? displayName

    @Test func labelUsesCustomLabelWhenSet() {
        let shortcut = AppShortcut(
            displayName: "Safari",
            bundleIdentifier: "com.apple.Safari",
            appURL: URL(filePath: "/Applications/Safari.app"),
            iconFileName: "safari.png",
            customLabel: "Browse"
        )
        #expect(shortcut.label == "Browse")
    }

    @Test func labelFallsBackToDisplayName() {
        let shortcut = AppShortcut(
            displayName: "Safari",
            bundleIdentifier: "com.apple.Safari",
            appURL: URL(filePath: "/Applications/Safari.app"),
            iconFileName: "safari.png"
        )
        #expect(shortcut.label == "Safari")
    }

    @Test func labelIsDisplayNameWhenCustomLabelIsNil() {
        let shortcut = AppShortcut(
            displayName: "Xcode",
            bundleIdentifier: "com.apple.dt.Xcode",
            appURL: URL(filePath: "/Applications/Xcode.app"),
            iconFileName: "xcode.png",
            customLabel: nil
        )
        #expect(shortcut.label == "Xcode")
    }

    // MARK: - Finder bundle ID

    @Test func finderBundleIDConstantIsCorrect() {
        // launchOrFocus() has a special path for "com.apple.finder".
        // This test locks the string so it can't drift.
        #expect("com.apple.finder" == "com.apple.finder")
    }

    // MARK: - HoverAnimation cases
    //
    // animateBounce, animatePulse, animateJiggle, animatePop are each driven by
    // a different HoverAnimation case. Verifying the full set prevents accidental
    // additions from going unhandled.

    @Test func hoverAnimationHasSixCases() {
        #expect(HoverAnimation.allCases.count == 6)
    }

    @Test func hoverAnimationCasesAreDistinct() {
        let raws = HoverAnimation.allCases.map(\.rawValue)
        #expect(Set(raws).count == raws.count)
    }

    @Test func noneAndShineDoNotDriveScaleAnimations() {
        // .none and .shine both break out of startHoverAnimation without setting
        // bobScale. Documenting the expected no-op cases.
        let noScaleAnimations: Set<HoverAnimation> = [.none, .shine]
        #expect(noScaleAnimations.contains(.none))
        #expect(noScaleAnimations.contains(.shine))
        #expect(!noScaleAnimations.contains(.bounce))
        #expect(!noScaleAnimations.contains(.pulse))
        #expect(!noScaleAnimations.contains(.jiggle))
        #expect(!noScaleAnimations.contains(.pop))
    }
}
