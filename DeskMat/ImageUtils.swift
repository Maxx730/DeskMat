import AppKit

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

    /// Resolves the directory URL to use for image loading.
    ///
    /// Prefers a security-scoped bookmark stored under `bookmarkKey` (saved when the user
    /// picked a directory via NSOpenPanel). Falls back to resolving `directoryPath` directly,
    /// which works for paths covered by entitlements such as `~/Pictures`.
    ///
    /// The caller is responsible for calling `stopAccessingSecurityScopedResource()` on the
    /// returned URL when `isSecurityScoped` is `true`.
    static func resolveDirectoryURL(
        directoryPath: String,
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
                return (url, true)
            }
        }
        let expanded = (directoryPath as NSString).expandingTildeInPath
        return (URL(fileURLWithPath: expanded), false)
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
