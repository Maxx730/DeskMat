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

    /// Returns a lightened version of a SwiftUI Color by the given factor (0.0–1.0).
    /// A factor of 0.3 means 30% of the gap to white is added.
    static func lightened(_ color: Color, by factor: Double = 0.3) -> Color {
        let nsColor = NSColor(color).usingColorSpace(.sRGB) ?? NSColor(color)
        return Color(
            red: nsColor.redComponent + (1.0 - nsColor.redComponent) * factor,
            green: nsColor.greenComponent + (1.0 - nsColor.greenComponent) * factor,
            blue: nsColor.blueComponent + (1.0 - nsColor.blueComponent) * factor,
            opacity: nsColor.alphaComponent
        )
    }

    /// Returns the average color of an NSImage.
    static func averageColor(of image: NSImage) -> Color? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
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
