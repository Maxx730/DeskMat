import Testing
import Foundation
import AppKit
@testable import DeskMat

// MARK: - ImageUtils Tests

struct ImageUtilsTests {

    // MARK: supportedExtensions

    @Test func supportedExtensionsContainsCommonFormats() {
        let exts = ImageUtils.supportedExtensions
        #expect(exts.contains("jpg"))
        #expect(exts.contains("jpeg"))
        #expect(exts.contains("png"))
        #expect(exts.contains("gif"))
        #expect(exts.contains("heic"))
        #expect(exts.contains("heif"))
        #expect(exts.contains("webp"))
        #expect(exts.contains("tiff"))
        #expect(exts.contains("tif"))
        #expect(exts.contains("bmp"))
    }

    // MARK: loadImages(at:)

    @Test func loadImagesReturnsEmptyForNonExistentDirectory() {
        let result = ImageUtils.loadImages(from: "/nonexistent/path/\(UUID().uuidString)")
        #expect(result.isEmpty)
    }

    @Test func loadImagesFiltersOutNonImageFiles() throws {
        let dir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        try Data().write(to: dir.appendingPathComponent("photo.jpg"))
        try Data().write(to: dir.appendingPathComponent("document.pdf"))
        try Data().write(to: dir.appendingPathComponent("script.sh"))

        let result = ImageUtils.loadImages(at: dir)
        #expect(result.count == 1)
        #expect(result[0].lastPathComponent == "photo.jpg")
    }

    @Test func loadImagesMatchesAllSupportedExtensions() throws {
        let dir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        for ext in ImageUtils.supportedExtensions {
            try Data().write(to: dir.appendingPathComponent("file.\(ext)"))
        }
        try Data().write(to: dir.appendingPathComponent("file.txt"))

        let result = ImageUtils.loadImages(at: dir)
        #expect(result.count == ImageUtils.supportedExtensions.count)
    }

    @Test func loadImagesIsCaseInsensitiveForExtensions() throws {
        let dir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        try Data().write(to: dir.appendingPathComponent("a.JPG"))
        try Data().write(to: dir.appendingPathComponent("b.Png"))
        try Data().write(to: dir.appendingPathComponent("c.HEIC"))

        let result = ImageUtils.loadImages(at: dir)
        #expect(result.count == 3)
    }

    @Test func loadImagesSkipsHiddenFiles() throws {
        let dir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        try Data().write(to: dir.appendingPathComponent("visible.jpg"))
        try Data().write(to: dir.appendingPathComponent(".hidden.jpg"))

        let result = ImageUtils.loadImages(at: dir)
        #expect(result.count == 1)
        #expect(result[0].lastPathComponent == "visible.jpg")
    }

    // MARK: loadImages(from:) — path string variant

    @Test func loadImagesFromPathExpandsTilde() throws {
        let dir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        try Data().write(to: dir.appendingPathComponent("img.png"))

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        guard dir.path.hasPrefix(home) else { return }
        let relativePath = "~" + dir.path.dropFirst(home.count)

        let result = ImageUtils.loadImages(from: relativePath)
        #expect(result.count == 1)
    }

    // MARK: loadImage(from:)

    @Test func loadImageReturnsNilForNilURL() async {
        let result = await ImageUtils.loadImage(from: nil)
        #expect(result == nil)
    }

    @Test func loadImageReturnsNilForNonExistentFile() async {
        let url = URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString).png")
        let result = await ImageUtils.loadImage(from: url)
        #expect(result == nil)
    }

    @Test func loadImageLoadsValidPNGFile() async throws {
        let dir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let fileURL = dir.appendingPathComponent("test.png")
        try makePNG(at: fileURL)

        let result = await ImageUtils.loadImage(from: fileURL)
        #expect(result != nil)
    }

    // MARK: resolveDirectoryURL

    @Test func resolveDirectoryURLFallsBackToPathWhenNoBookmark() {
        let key = "imageutils_test_\(UUID().uuidString)"
        UserDefaults.standard.removeObject(forKey: key)

        let (url, isSecurityScoped) = ImageUtils.resolveURL(path: "/tmp", bookmarkKey: key)

        #expect(!isSecurityScoped)
        #expect(url.path == "/tmp")
    }

    @Test func resolveDirectoryURLFallsBackOnInvalidBookmarkData() {
        let key = "imageutils_test_\(UUID().uuidString)"
        UserDefaults.standard.set(Data([0x00, 0x01, 0x02]), forKey: key)
        defer { UserDefaults.standard.removeObject(forKey: key) }

        let (_, isSecurityScoped) = ImageUtils.resolveURL(path: "/tmp", bookmarkKey: key)

        #expect(!isSecurityScoped)
    }

    // MARK: saveBookmark

    @Test func saveBookmarkDoesNotCrashForValidURL() {
        let key = "imageutils_test_\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: key) }
        ImageUtils.saveBookmark(for: URL(fileURLWithPath: NSTemporaryDirectory()), bookmarkKey: key)
    }

    // MARK: Helpers

    private func makeTemporaryDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makePNG(at url: URL) throws {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 1, pixelsHigh: 1,
            bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false,
            colorSpaceName: .calibratedRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ) else { throw ImageTestError.bitmapCreationFailed }
        rep.setColor(.red, atX: 0, y: 0)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            throw ImageTestError.pngEncodingFailed
        }
        try png.write(to: url)
    }
}

private enum ImageTestError: Error {
    case bitmapCreationFailed
    case pngEncodingFailed
}
