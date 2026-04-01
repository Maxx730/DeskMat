import SwiftUI

struct ImageWidget: View {
    @AppStorage("showLabels") private var showLabels = true
    @AppStorage("imageWidgetDirectory") private var imageWidgetDirectory = "~/Pictures"
    @State private var images: [URL] = []
    @State private var currentImage: NSImage?
    @State private var panOffset: CGFloat = 0
    @State private var imageVersion: Int = 0

    private static let widgetWidth: CGFloat = 128
    private static let widgetHeight: CGFloat = 64
    private static let panScale: CGFloat = 2.4
    private static var scaledWidth: CGFloat { widgetWidth * panScale }
    private static var maxPan: CGFloat { (scaledWidth - widgetWidth) / 2 }

    static let bookmarkKey = "imageWidgetDirectoryBookmark"

    var body: some View {
        VStack(spacing: 10) {
            DockWidget(cells: 2) {
                if let nsImage = currentImage {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: Self.scaledWidth, height: Self.widgetHeight)
                        .offset(x: panOffset)
                        .frame(width: Self.widgetWidth, height: Self.widgetHeight)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .contentShape(RoundedRectangle(cornerRadius: 10))
                } else {
                    placeholder
                }
            }
            if showLabels {
                Text("Images")
                    .font(.caption2)
                    .lineLimit(1)
                    .frame(width: Self.widgetWidth)
                    .truncationMode(.tail)
            }
        }
        .task(id: imageWidgetDirectory) {
            let (directoryURL, isSecurityScoped) = ImageUtils.resolveURL(
                path: imageWidgetDirectory,
                bookmarkKey: Self.bookmarkKey
            )
            defer { if isSecurityScoped { directoryURL.stopAccessingSecurityScopedResource() } }

            try? await Task.sleep(for: .seconds(1))
            images = ImageUtils.loadImages(at: directoryURL)
            currentImage = await ImageUtils.loadImage(from: images.randomElement())
            imageVersion += 1
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                currentImage = await ImageUtils.loadImage(from: images.randomElement())
                imageVersion += 1
            }
        }
        .onChange(of: imageVersion) { _, _ in
            startPanAnimation()
        }
    }

    private func startPanAnimation() {
        let start = CGFloat.random(in: -Self.maxPan...Self.maxPan)
        var end = CGFloat.random(in: -Self.maxPan...Self.maxPan)
        while abs(end - start) < Self.maxPan * 0.5 {
            end = CGFloat.random(in: -Self.maxPan...Self.maxPan)
        }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { panOffset = start }
        withAnimation(.linear(duration: 15)) { panOffset = end }
    }

    private var placeholder: some View {
        Image(systemName: "photo")
            .font(.system(size: 28))
            .foregroundStyle(.white.opacity(0.8))
    }
}
