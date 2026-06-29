import Testing
import AppKit
import SwiftUI
@testable import DeskMat

private func sRGBComponents(of color: Color) -> (r: CGFloat, g: CGFloat, b: CGFloat)? {
    guard let ns = NSColor(color).usingColorSpace(.sRGB) else { return nil }
    return (ns.redComponent, ns.greenComponent, ns.blueComponent)
}

// MARK: - ContrastingTextColorLuminanceTests

@Suite struct ContrastingTextColorLuminanceTests {

    @Test func darkBackgroundYieldsLightText() {
        let result = MediaControlWidget.contrastingTextColor(for: Color(red: 0, green: 0, blue: 0))
        let (r, g, b) = sRGBComponents(of: result)!
        #expect(r > 0.8)
        #expect(g > 0.8)
        #expect(b > 0.8)
    }

    @Test func lightBackgroundYieldsDarkText() {
        let result = MediaControlWidget.contrastingTextColor(for: Color(red: 1, green: 1, blue: 1))
        let (r, g, b) = sRGBComponents(of: result)!
        #expect(r < 0.2)
        #expect(g < 0.2)
        #expect(b < 0.2)
    }

    @Test func midGreyAboveThresholdYieldsDarkText() {
        // #808080 — luminance ≈ 0.216 > 0.179 → dark text
        let result = MediaControlWidget.contrastingTextColor(for: Color(red: 0x80 / 255.0, green: 0x80 / 255.0, blue: 0x80 / 255.0))
        let (r, g, b) = sRGBComponents(of: result)!
        #expect(r < 0.2)
        #expect(g < 0.2)
        #expect(b < 0.2)
    }

    @Test func midGreyBelowThresholdYieldsLightText() {
        // #606060 — luminance ≈ 0.118 < 0.179 → light text
        let result = MediaControlWidget.contrastingTextColor(for: Color(red: 0x60 / 255.0, green: 0x60 / 255.0, blue: 0x60 / 255.0))
        let (r, g, b) = sRGBComponents(of: result)!
        #expect(r > 0.8)
        #expect(g > 0.8)
        #expect(b > 0.8)
    }

    @Test func defaultTintStrengthIs0_15() {
        // Black background: pure base = 1.0. With tintStrength=0.15, result ≈ 0.85.
        // Delta from pure base must be ≤ 0.15 per channel.
        let result = MediaControlWidget.contrastingTextColor(for: Color(red: 0, green: 0, blue: 0))
        let (r, g, b) = sRGBComponents(of: result)!
        #expect(abs(1.0 - r) <= 0.15 + 1e-9)
        #expect(abs(1.0 - g) <= 0.15 + 1e-9)
        #expect(abs(1.0 - b) <= 0.15 + 1e-9)
    }

    @Test func zeroTintStrengthReturnsPureBase() {
        let result = MediaControlWidget.contrastingTextColor(for: Color(red: 0, green: 0, blue: 0), tintStrength: 0)
        let (r, g, b) = sRGBComponents(of: result)!
        #expect(abs(r - 1.0) < 1e-6)
        #expect(abs(g - 1.0) < 1e-6)
        #expect(abs(b - 1.0) < 1e-6)
    }

    @Test func fullTintStrengthReturnsBgColor() {
        let bgColor = Color(red: 0.6, green: 0.3, blue: 0.8)
        let result = MediaControlWidget.contrastingTextColor(for: bgColor, tintStrength: 1.0)
        let (inputR, inputG, inputB) = sRGBComponents(of: bgColor)!
        let (r, g, b) = sRGBComponents(of: result)!
        #expect(abs(r - Double(inputR)) < 1e-5)
        #expect(abs(g - Double(inputG)) < 1e-5)
        #expect(abs(b - Double(inputB)) < 1e-5)
    }

    @Test func invalidNSColorFallbackReturnsWhite() {
        // Pattern colors cannot convert to sRGB, triggering the guard fallback → .white
        let patternImage = NSImage(size: NSSize(width: 1, height: 1))
        let patternColor = Color(NSColor(patternImage: patternImage))
        let result = MediaControlWidget.contrastingTextColor(for: patternColor)
        let (r, g, b) = sRGBComponents(of: result)!
        #expect(abs(r - 1.0) < 1e-6)
        #expect(abs(g - 1.0) < 1e-6)
        #expect(abs(b - 1.0) < 1e-6)
    }
}

// MARK: - ContrastingTextColorTintTests

@Suite struct ContrastingTextColorTintTests {

    @Test func redBackgroundTintsLightText() {
        // Dark red: luminance < 0.179 → light base, R channel gets red tint
        let result = MediaControlWidget.contrastingTextColor(for: Color(red: 0.5, green: 0, blue: 0))
        let (r, g, b) = sRGBComponents(of: result)!
        #expect(r > g)
        #expect(r > b)
    }

    @Test func blueBackgroundTintsDarkText() {
        // Light blue (#8080FF): high luminance → dark base, B channel gets blue tint
        let result = MediaControlWidget.contrastingTextColor(for: Color(red: 0.502, green: 0.502, blue: 1.0))
        let (r, g, b) = sRGBComponents(of: result)!
        #expect(b > r)
        #expect(b > g)
    }

    @Test func tintStrengthScalesLinearly() {
        // Black background: pure base = 1.0. Deviations at 0.15 and 0.30 should be 2:1.
        let bg = Color(red: 0, green: 0, blue: 0)
        let result15 = MediaControlWidget.contrastingTextColor(for: bg, tintStrength: 0.15)
        let result30 = MediaControlWidget.contrastingTextColor(for: bg, tintStrength: 0.30)
        let (r15, _, _) = sRGBComponents(of: result15)!
        let (r30, _, _) = sRGBComponents(of: result30)!
        let delta15 = 1.0 - r15
        let delta30 = 1.0 - r30
        #expect(abs(delta30 / delta15 - 2.0) < 0.01)
    }
}
