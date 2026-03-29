import AppKit
import SwiftUI

enum ImageUtils {

    static let supportedExtensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "heic", "heif", "webp", "tiff", "tif", "bmp"
    ]

    /// Returns all image file URLs in the directory at the given path string.
    static func loadImages(from directoryPath: String) -> [URL] {
        let expanded = (directoryPath as NSString).expandingTildeInPath
        return loadImages(at: URL(fileURLWithPath: expanded))
    }

    /// Returns all image file URLs in the given directory URL.
    static func loadImages(at directoryURL: URL) -> [URL] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return contents.filter { supportedExtensions.contains($0.pathExtension.lowercased()) }
    }

    /// Asynchronously loads an NSImage from a file URL on a background thread.
    static func loadImage(from url: URL?) async -> NSImage? {
        guard let url else { return nil }
        return await Task.detached(priority: .background) {
            NSImage(contentsOf: url)
        }.value
    }

    /// Resolves the URL to use for file or directory access.
    ///
    /// Prefers a security-scoped bookmark stored under `bookmarkKey` (saved when the user
    /// picked a path via NSOpenPanel). Falls back to resolving `path` directly, which works
    /// for paths covered by entitlements such as `~/Pictures`.
    ///
    /// If the resolved bookmark is stale it is refreshed automatically.
    /// The caller is responsible for calling `stopAccessingSecurityScopedResource()` on the
    /// returned URL when `isSecurityScoped` is `true`.
    static func resolveURL(
        path: String,
        bookmarkKey: String
    ) -> (url: URL, isSecurityScoped: Bool) {
        if let bookmarkData = UserDefaults.standard.data(forKey: bookmarkKey) {
            var isStale = false
            if let url = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ), url.startAccessingSecurityScopedResource() {
                if isStale {
                    saveBookmark(for: url, bookmarkKey: bookmarkKey)
                }
                return (url, true)
            }
        }
        let expanded = (path as NSString).expandingTildeInPath
        return (URL(fileURLWithPath: expanded), false)
    }

    // MARK: - Bitmap Sampling

    /// Resamples an NSImage to the given pixel dimensions and returns every pixel as a Color,
    /// in row-major order (left-to-right, top-to-bottom).
    /// Returns nil if the image cannot be rasterised.
    static func pixels(from image: NSImage, width: Int, height: Int) -> [Color]? {
        guard let bitmap = rasterise(image, width: width, height: height) else { return nil }
        return pixels(fromRep: bitmap)
    }

    /// Resamples an NSImage to the given pixel dimensions and returns a 2D grid of Colors
    /// indexed as `[row][column]`.
    /// Returns nil if the image cannot be rasterised.
    static func pixelGrid(from image: NSImage, columns: Int, rows: Int) -> [[Color]]? {
        guard let flat = pixels(from: image, width: columns, height: rows) else { return nil }
        return (0..<rows).map { row in
            Array(flat[(row * columns)..<(row * columns + columns)])
        }
    }

    /// Returns a 2D grid of Colors from an existing bitmap representation indexed as `[row][column]`.
    /// Reads the rep directly when it is already at the target size; otherwise wraps it in an
    /// NSImage and rasterises to the requested dimensions.
    /// Returns nil if the pixels cannot be read.
    static func pixelGrid(from rep: NSBitmapImageRep, columns: Int, rows: Int) -> [[Color]]? {
        if rep.pixelsWide == columns && rep.pixelsHigh == rows {
            guard let flat = pixels(fromRep: rep) else { return nil }
            return (0..<rows).map { row in
                Array(flat[(row * columns)..<(row * columns + columns)])
            }
        }
        let image = NSImage(size: NSSize(width: rep.pixelsWide, height: rep.pixelsHigh))
        image.addRepresentation(rep)
        return pixelGrid(from: image, columns: columns, rows: rows)
    }

    /// Returns the color of the single pixel nearest to the normalised position (0–1, 0–1)
    /// within the image, without resampling the entire image.
    /// Returns nil if the image cannot be rasterised.
    static func pixel(from image: NSImage, atNormalisedX nx: Double, y ny: Double) -> Color? {
        let w = max(1, Int(image.size.width))
        let h = max(1, Int(image.size.height))
        guard let bitmap = rasterise(image, width: w, height: h) else { return nil }
        let px = min(w - 1, Int(nx * Double(w)))
        let py = min(h - 1, Int(ny * Double(h)))
        guard let nsColor = bitmap.colorAt(x: px, y: py)?.usingColorSpace(.sRGB) else { return nil }
        return Color(
            red: nsColor.redComponent,
            green: nsColor.greenComponent,
            blue: nsColor.blueComponent,
            opacity: nsColor.alphaComponent
        )
    }

    // MARK: - Sprite Sheet

    /// Splits an image into frames of `frameWidthPx` source pixels wide, reading left to right.
    /// Remaining pixels that don't fill a complete frame are ignored.
    /// Returns one `NSBitmapImageRep` per frame using a fast memory copy.
    static func extractFrames(from image: NSImage, frameWidthPx: Int) -> [NSBitmapImageRep] {
        let srcW = Int(image.size.width.rounded())
        let srcH = Int(image.size.height.rounded())
        guard frameWidthPx > 0, srcW > 0, srcH > 0 else { return [] }
        let numFrames = srcW / frameWidthPx
        guard numFrames > 0 else { return [] }
        guard let fullBitmap = rasterise(image, width: srcW, height: srcH),
              let srcData = fullBitmap.bitmapData else { return [] }

        let bytesPerPixel = fullBitmap.bitsPerPixel / 8
        let srcBytesPerRow = fullBitmap.bytesPerRow

        return (0..<numFrames).compactMap { frameIndex in
            let xOffset = frameIndex * frameWidthPx
            guard let frameBitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: frameWidthPx, pixelsHigh: srcH,
                bitsPerSample: 8, samplesPerPixel: 4,
                hasAlpha: true, isPlanar: false,
                colorSpaceName: .calibratedRGB,
                bytesPerRow: 0, bitsPerPixel: 0
            ), let dstData = frameBitmap.bitmapData else { return nil }

            let dstBytesPerRow = frameBitmap.bytesPerRow
            let copyWidth = frameWidthPx * bytesPerPixel
            for py in 0..<srcH {
                memcpy(
                    dstData.advanced(by: py * dstBytesPerRow),
                    srcData.advanced(by: py * srcBytesPerRow + xOffset * bytesPerPixel),
                    copyWidth
                )
            }
            return frameBitmap
        }
    }

    // MARK: - Private helpers

    /// Draws `image` into a bitmap of the requested size.
    /// Uses no interpolation to preserve hard pixel edges (suitable for pixel art).
    private static func rasterise(_ image: NSImage, width: Int, height: Int) -> NSBitmapImageRep? {
        guard let rep = NSBitmapImageRep(
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
        ) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .none
        image.draw(in: NSRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    /// Reads every pixel from an existing bitmap rep in row-major order.
    private static func pixels(fromRep rep: NSBitmapImageRep) -> [Color]? {
        let width = rep.pixelsWide
        let height = rep.pixelsHigh
        guard width > 0, height > 0 else { return nil }
        var result = [Color]()
        result.reserveCapacity(width * height)
        for y in 0..<height {
            for x in 0..<width {
                guard let nsColor = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else {
                    result.append(.black)
                    continue
                }
                result.append(Color(
                    red: nsColor.redComponent,
                    green: nsColor.greenComponent,
                    blue: nsColor.blueComponent,
                    opacity: nsColor.alphaComponent
                ))
            }
        }
        return result
    }

    /// Saves a security-scoped bookmark for the given URL to UserDefaults under `bookmarkKey`.
    /// Call this immediately after a successful NSOpenPanel selection.
    static func saveBookmark(for url: URL, bookmarkKey: String) {
        guard let bookmarkData = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else { return }
        UserDefaults.standard.set(bookmarkData, forKey: bookmarkKey)
    }
}
