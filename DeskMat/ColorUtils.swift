import AppKit
import SwiftUI

enum ColorUtils {

    /// Returns the average color of an application's icon, given its bundle identifier.
    /// Returns nil if the app can't be found or the icon can't be processed.
    static func averageColor(forBundleIdentifier bundleID: String) -> Color? {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
              let bundle = Bundle(url: appURL),
              let iconName = bundle.infoDictionary?["CFBundleIconFile"] as? String ?? bundle.infoDictionary?["CFBundleIconName"] as? String else {
            // Fall back to NSWorkspace icon
            return averageColor(of: NSWorkspace.shared.icon(forFile: NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)?.path(percentEncoded: false) ?? ""))
        }

        let iconPath = bundle.pathForImageResource(iconName) ?? bundle.path(forResource: iconName, ofType: "icns")
        if let path = iconPath, let image = NSImage(contentsOfFile: path) {
            return averageColor(of: image)
        }

        // Fall back to NSWorkspace icon for the app
        if let appPath = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)?.path(percentEncoded: false) {
            return averageColor(of: NSWorkspace.shared.icon(forFile: appPath))
        }

        return nil
    }

    /// Returns a darkened version of a SwiftUI Color by the given factor (0.0–1.0).
    /// A factor of 0.8 means the color retains 80% of its brightness.
    static func darkened(_ color: Color, by factor: Double = 0.7) -> Color {
        let nsColor = NSColor(color).usingColorSpace(.sRGB) ?? NSColor(color)
        return Color(
            red: nsColor.redComponent * factor,
            green: nsColor.greenComponent * factor,
            blue: nsColor.blueComponent * factor,
            opacity: nsColor.alphaComponent
        )
    }


    /// Returns a copy of the color with its HSB brightness (V) increased by the given amount (0.0–1.0), clamped to 1.0.
    static func brightenedHSV(_ color: Color, by amount: Double = 0.2) -> Color {
        let nsColor = NSColor(color).usingColorSpace(.sRGB) ?? NSColor(color)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        nsColor.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return Color(hue: h, saturation: s, brightness: min(b + amount, 1.0), opacity: a)
    }

    /// Converts a SwiftUI Color to a hex string (e.g. "#ff0000ff" with alpha).
    static func toHex(_ color: Color) -> String {
        let nsColor = NSColor(color).usingColorSpace(.sRGB) ?? NSColor(color)
        let r = Int((nsColor.redComponent * 255).rounded())
        let g = Int((nsColor.greenComponent * 255).rounded())
        let b = Int((nsColor.blueComponent * 255).rounded())
        let a = Int((nsColor.alphaComponent * 255).rounded())
        return String(format: "#%02x%02x%02x%02x", r, g, b, a)
    }

    /// Converts a hex string (e.g. "#ff0000ff") back to a SwiftUI Color.
    static func fromHex(_ hex: String) -> Color {
        var raw = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        if raw.count == 6 { raw += "ff" }
        guard raw.count == 8, let value = UInt64(raw, radix: 16) else { return .black }
        let r = Double((value >> 24) & 0xff) / 255
        let g = Double((value >> 16) & 0xff) / 255
        let b = Double((value >> 8) & 0xff) / 255
        let a = Double(value & 0xff) / 255
        return Color(red: r, green: g, blue: b, opacity: a)
    }

    /// Returns the average color of an NSImage.
    static func averageColor(of image: NSImage) -> Color? {
        guard image.tiffRepresentation != nil else {
            return nil
        }

        // Sample at a small size for performance
        let sampleSize = 64
        let smallImage = NSImage(size: NSSize(width: sampleSize, height: sampleSize))
        smallImage.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(x: 0, y: 0, width: sampleSize, height: sampleSize))
        smallImage.unlockFocus()

        guard let smallTiff = smallImage.tiffRepresentation,
              let smallBitmap = NSBitmapImageRep(data: smallTiff) else {
            return nil
        }

        var totalR: Double = 0
        var totalG: Double = 0
        var totalB: Double = 0
        var count: Double = 0

        for x in 0..<smallBitmap.pixelsWide {
            for y in 0..<smallBitmap.pixelsHigh {
                guard let color = smallBitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                let alpha = color.alphaComponent
                // Skip fully transparent pixels
                if alpha < 0.1 { continue }
                totalR += color.redComponent * alpha
                totalG += color.greenComponent * alpha
                totalB += color.blueComponent * alpha
                count += alpha
            }
        }

        guard count > 0 else { return nil }

        let darkenFactor = 0.6
        return Color(
            red: (totalR / count) * darkenFactor,
            green: (totalG / count) * darkenFactor,
            blue: (totalB / count) * darkenFactor
        )
    }
}
