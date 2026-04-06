import Testing
import Foundation
import AppKit
import SwiftUI
@testable import DeskMat

// MARK: - ColorUtils Tests

struct ColorUtilsTests {

    @Test func averageColorOfSolidRedImage() {
        let image = NSImage(size: NSSize(width: 10, height: 10))
        image.lockFocus()
        NSColor.red.drawSwatch(in: NSRect(x: 0, y: 0, width: 10, height: 10))
        image.unlockFocus()

        let color = ColorUtils.averageColor(of: image)
        #expect(color != nil)
    }

    @Test func averageColorOfSolidGreenImage() {
        let image = NSImage(size: NSSize(width: 10, height: 10))
        image.lockFocus()
        NSColor.green.drawSwatch(in: NSRect(x: 0, y: 0, width: 10, height: 10))
        image.unlockFocus()

        let color = ColorUtils.averageColor(of: image)
        #expect(color != nil)
    }

    @Test func averageColorReturnsNilForTransparentBitmap() {
        let width = 10
        let height = 10
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .calibratedRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            Issue.record("Failed to create bitmap")
            return
        }
        for x in 0..<width {
            for y in 0..<height {
                bitmap.setColor(NSColor(red: 0, green: 0, blue: 0, alpha: 0), atX: x, y: y)
            }
        }
        let image = NSImage(size: NSSize(width: width, height: height))
        image.addRepresentation(bitmap)

        let color = ColorUtils.averageColor(of: image)
        #expect(color == nil)
    }

    @Test func averageColorForKnownBundleID() {
        let color = ColorUtils.averageColor(forBundleIdentifier: "com.apple.finder")
        #expect(color != nil)
    }

    @Test func averageColorForInvalidBundleIDReturnsColor() {
        let color = ColorUtils.averageColor(forBundleIdentifier: "com.nonexistent.fakebundle.xyz")
        #expect(color != nil)
    }

    @Test func averageColorAppliesDarkenFactor() {
        let image = NSImage(size: NSSize(width: 10, height: 10))
        image.lockFocus()
        NSColor.white.drawSwatch(in: NSRect(x: 0, y: 0, width: 10, height: 10))
        image.unlockFocus()

        let color = ColorUtils.averageColor(of: image)
        #expect(color != nil)
    }

    // MARK: - darkened

    @Test func darkenedReducesBrightness() {
        let white = Color.white
        let darkened = ColorUtils.darkened(white, by: 0.5)
        let ns = NSColor(darkened).usingColorSpace(.sRGB)!

        #expect(ns.redComponent < 0.6)
        #expect(ns.greenComponent < 0.6)
        #expect(ns.blueComponent < 0.6)
    }

    @Test func darkenedByZeroProducesBlack() {
        let color = Color.red
        let darkened = ColorUtils.darkened(color, by: 0.0)
        let ns = NSColor(darkened).usingColorSpace(.sRGB)!

        #expect(ns.redComponent < 0.01)
        #expect(ns.greenComponent < 0.01)
        #expect(ns.blueComponent < 0.01)
    }

    @Test func darkenedByOnePreservesColor() {
        let color = Color.blue
        let darkened = ColorUtils.darkened(color, by: 1.0)
        let original = NSColor(color).usingColorSpace(.sRGB)!
        let result = NSColor(darkened).usingColorSpace(.sRGB)!

        #expect(abs(result.redComponent - original.redComponent) < 0.01)
        #expect(abs(result.greenComponent - original.greenComponent) < 0.01)
        #expect(abs(result.blueComponent - original.blueComponent) < 0.01)
    }

    @Test func darkenedPreservesAlpha() {
        let color = Color.red.opacity(0.5)
        let darkened = ColorUtils.darkened(color, by: 0.5)
        let ns = NSColor(darkened).usingColorSpace(.sRGB)!

        #expect(abs(ns.alphaComponent - 0.5) < 0.01)
    }

    // MARK: - brightenedHSV

    @Test func brightenedHSVIncreasesValue() {
        let color = Color(hue: 0.5, saturation: 0.8, brightness: 0.4)
        let brightened = ColorUtils.brightenedHSV(color, by: 0.2)
        let ns = NSColor(brightened).usingColorSpace(.sRGB)!
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ns.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        #expect(abs(b - 0.6) < 0.01)
    }

    @Test func brightenedHSVPreservesHueAndSaturation() {
        let color = Color(hue: 0.3, saturation: 0.7, brightness: 0.5)
        let brightened = ColorUtils.brightenedHSV(color, by: 0.1)
        let ns = NSColor(brightened).usingColorSpace(.sRGB)!
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ns.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        #expect(abs(h - 0.3) < 0.01)
        #expect(abs(s - 0.7) < 0.01)
    }

    @Test func brightenedHSVClampsToOne() {
        let color = Color(hue: 0.5, saturation: 0.5, brightness: 0.9)
        let brightened = ColorUtils.brightenedHSV(color, by: 0.5)
        let ns = NSColor(brightened).usingColorSpace(.sRGB)!
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ns.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        #expect(b <= 1.0)
        #expect(abs(b - 1.0) < 0.01)
    }

    @Test func brightenedHSVPreservesAlpha() {
        let color = Color(hue: 0.5, saturation: 0.5, brightness: 0.5).opacity(0.6)
        let brightened = ColorUtils.brightenedHSV(color, by: 0.1)
        let ns = NSColor(brightened).usingColorSpace(.sRGB)!
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ns.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        #expect(abs(a - 0.6) < 0.01)
    }

    @Test func brightenedHSVByZeroIsUnchanged() {
        let color = Color(hue: 0.4, saturation: 0.6, brightness: 0.5)
        let brightened = ColorUtils.brightenedHSV(color, by: 0.0)
        let ns = NSColor(brightened).usingColorSpace(.sRGB)!
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ns.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        #expect(abs(b - 0.5) < 0.01)
    }

    // MARK: - toHex / fromHex

    @Test func toHexProducesHashPrefixedEightCharString() {
        let hex = ColorUtils.toHex(.red)
        #expect(hex.hasPrefix("#"))
        #expect(hex.count == 9)
    }

    @Test func toHexRedColor() {
        let hex = ColorUtils.toHex(Color(red: 1, green: 0, blue: 0, opacity: 1))
        #expect(hex.lowercased() == "#ff0000ff")
    }

    @Test func toHexBlackColor() {
        let hex = ColorUtils.toHex(Color(red: 0, green: 0, blue: 0, opacity: 1))
        #expect(hex.lowercased() == "#000000ff")
    }

    @Test func toHexEncodesAlpha() {
        let hex = ColorUtils.toHex(Color(red: 1, green: 1, blue: 1, opacity: 0))
        #expect(hex.lowercased() == "#ffffff00")
    }

    @Test func fromHexDecodesBlack() {
        let color = ColorUtils.fromHex("#000000ff")
        let ns = NSColor(color).usingColorSpace(.sRGB)!
        #expect(ns.redComponent < 0.01)
        #expect(ns.greenComponent < 0.01)
        #expect(ns.blueComponent < 0.01)
        #expect(abs(ns.alphaComponent - 1.0) < 0.01)
    }

    @Test func fromHexDecodesRed() {
        let color = ColorUtils.fromHex("#ff0000ff")
        let ns = NSColor(color).usingColorSpace(.sRGB)!
        #expect(abs(ns.redComponent - 1.0) < 0.01)
        #expect(ns.greenComponent < 0.01)
        #expect(ns.blueComponent < 0.01)
    }

    @Test func fromHexExpandsSixCharToEight() {
        let color = ColorUtils.fromHex("#ff0000")
        let ns = NSColor(color).usingColorSpace(.sRGB)!
        #expect(abs(ns.redComponent - 1.0) < 0.01)
        #expect(abs(ns.alphaComponent - 1.0) < 0.01)
    }

    @Test func fromHexInvalidInputReturnsBlack() {
        let color = ColorUtils.fromHex("notahex")
        let ns = NSColor(color).usingColorSpace(.sRGB)!
        #expect(ns.redComponent < 0.01)
        #expect(ns.greenComponent < 0.01)
        #expect(ns.blueComponent < 0.01)
    }

    @Test func toHexFromHexRoundTrips() {
        let original = Color(red: 0.4, green: 0.6, blue: 0.8, opacity: 0.9)
        let hex = ColorUtils.toHex(original)
        let recovered = ColorUtils.fromHex(hex)
        let ns = NSColor(recovered).usingColorSpace(.sRGB)!
        let nsOriginal = NSColor(original).usingColorSpace(.sRGB)!
        #expect(abs(ns.redComponent - nsOriginal.redComponent) < 0.01)
        #expect(abs(ns.greenComponent - nsOriginal.greenComponent) < 0.01)
        #expect(abs(ns.blueComponent - nsOriginal.blueComponent) < 0.01)
        #expect(abs(ns.alphaComponent - nsOriginal.alphaComponent) < 0.01)
    }
}
