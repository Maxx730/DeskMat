import SwiftUI

struct LEDBoardWidget: View {
    static let widthModeKey = "ledBoardIsWide"
    static let bookmarkKey = "ledBoardImageBookmark"
    static let imagePathKey = "ledBoardImagePath"
    static let scrollSpeedKey = "ledBoardScrollSpeed"
    static let frameSpeedKey = "ledBoardFrameSpeed"

    @AppStorage("showLabels") private var showLabels = true
    @AppStorage(LEDBoardWidget.imagePathKey) private var ledBoardImagePath = ""
    @AppStorage(LEDBoardWidget.scrollSpeedKey) private var scrollSpeed = 80
    @AppStorage(LEDBoardWidget.frameSpeedKey) private var frameSpeed = 150
    @AppStorage(LEDBoardWidget.widthModeKey) private var isWide = true
    @State private var frames: [[[Color?]]] = []
    @State private var currentFrame: Int = 0
    @State private var scrollOffset: Int = 0
    @State private var framesVersion: Int = 0

    private static let dotsPerCell = 16
    private static let rows = 16
    private static let sourceFrameWidth = 16

    private var cellCount: Int { isWide ? 2 : 1 }
    private var columns: Int { cellCount * Self.dotsPerCell }

    var body: some View {
        VStack(spacing: 10) {
            DockWidget(cells: cellCount, hoverEffect: false) {
                LEDGrid(
                    columns: columns,
                    rows: Self.rows,
                    pixels: frames.isEmpty ? [] : frames[currentFrame],
                    scrollOffset: scrollOffset
                )
                .padding(4)
            }
            // Loads the image and drives the scroll loop; re-runs on path or width change
            .task(id: "\(ledBoardImagePath)|\(isWide)") {
                frames = []
                currentFrame = 0
                scrollOffset = 0
                framesVersion = 0
                guard !ledBoardImagePath.isEmpty else { return }

                let (url, isSecurityScoped) = ImageUtils.resolveURL(
                    path: ledBoardImagePath,
                    bookmarkKey: Self.bookmarkKey
                )
                defer { if isSecurityScoped { url.stopAccessingSecurityScopedResource() } }
                guard let image = await ImageUtils.loadImage(from: url) else { return }

                let cols = columns
                let rows = Self.rows
                frames = await Task.detached(priority: .background) {
                    await ImageUtils.extractFrames(from: image, frameWidthPx: Self.sourceFrameWidth)
                        .map { Self.buildPixelGrid(from: $0, columns: cols, rows: rows) }
                }.value
                framesVersion += 1

                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(scrollSpeed))
                    scrollOffset += 1
                }
            }
            // Cycles animation frames independently of scrolling
            .task(id: framesVersion) {
                guard framesVersion > 0 else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(frameSpeed))
                    let count = frames.count
                    guard count > 0 else { return }
                    currentFrame = (currentFrame + 1) % count
                }
            }
            if showLabels {
                Text(Strings.Widgets.ledBoard)
                    .font(.caption2)
                    .lineLimit(1)
                    .frame(width: DockWidget<EmptyView>.width(for: cellCount))
                    .truncationMode(.tail)
            }
        }
        .contextMenu {
            Button(isWide ? Strings.Settings.ledBoardCompact : Strings.Settings.ledBoardWide) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                    isWide.toggle()
                }
            }
            .disabled(ledBoardImagePath.isEmpty)
        }
    }

    /// Returns (scaledWidth, scaledHeight, xOffset, yOffset) for fitting
    /// a source of `srcW × srcH` into a grid of `cols × rows` cells.
    nonisolated static func gridFitMetrics(srcW: Int, srcH: Int, cols: Int, rows: Int)
        -> (scaledW: Int, scaledH: Int, xOff: Int, yOff: Int) {
        let aspect = CGFloat(srcW) / CGFloat(srcH)
        let gridAspect = CGFloat(cols) / CGFloat(rows)
        let scaledW: Int
        let scaledH: Int
        if aspect >= gridAspect {
            scaledW = cols
            scaledH = max(1, Int((CGFloat(cols) / aspect).rounded()))
        } else {
            scaledH = rows
            scaledW = max(1, Int((CGFloat(rows) * aspect).rounded()))
        }
        return (scaledW, scaledH, (cols - scaledW) / 2, (rows - scaledH) / 2)
    }

    nonisolated private static func buildPixelGrid(from frameRep: NSBitmapImageRep, columns: Int, rows: Int) -> [[Color?]] {
        let metrics = Self.gridFitMetrics(srcW: frameRep.pixelsWide, srcH: frameRep.pixelsHigh, cols: columns, rows: rows)
        let sampledCols = metrics.scaledW
        let sampledRows = metrics.scaledH
        let colOffset = metrics.xOff
        let rowOffset = metrics.yOff

        guard let sampled = ImageUtils.pixelGrid(from: frameRep, columns: sampledCols, rows: sampledRows) else {
            return Array(repeating: Array(repeating: nil, count: columns), count: rows)
        }

        var grid: [[Color?]] = Array(repeating: Array(repeating: nil, count: columns), count: rows)
        for row in 0..<sampledRows {
            for col in 0..<sampledCols {
                let ns = NSColor(sampled[row][col]).usingColorSpace(.sRGB)
                if let ns, ns.alphaComponent >= 0.5 {
                    grid[row + rowOffset][col + colOffset] = Color(
                        red: ns.redComponent,
                        green: ns.greenComponent,
                        blue: ns.blueComponent
                    )
                }
            }
        }
        return grid
    }
}

// MARK: - LED Grid

private struct LEDGrid: View {
    let columns: Int
    let rows: Int
    let pixels: [[Color?]]
    let scrollOffset: Int

    var body: some View {
        Canvas { context, size in
            let cellW = size.width / CGFloat(columns)
            let cellH = size.height / CGFloat(rows)
            let dotDiameter = min(cellW, cellH) * 0.7

            // Sprite scrolls from right to left, looping once it fully exits left
            let loopWidth = columns * 2
            let spriteLeft = columns - (scrollOffset % loopWidth)

            for row in 0..<rows {
                for col in 0..<columns {
                    let isCorner = (row == 0 || row == rows - 1) && (col == 0 || col == columns - 1)
                    guard !isCorner else { continue }

                    let cx = (CGFloat(col) + 0.5) * cellW
                    let cy = (CGFloat(row) + 0.5) * cellH
                    let rect = CGRect(
                        x: cx - dotDiameter / 2,
                        y: cy - dotDiameter / 2,
                        width: dotDiameter,
                        height: dotDiameter
                    )

                    let spriteCol = col - spriteLeft
                    let pixelRow = pixels.isEmpty ? nil : pixels[row]
                    let spriteColor: Color? = (pixelRow != nil && spriteCol >= 0 && spriteCol < pixelRow!.count)
                        ? pixelRow![spriteCol]
                        : nil

                    context.fill(Path(ellipseIn: rect), with: .color(spriteColor ?? .black.opacity(0.25)))
                }
            }
        }
    }
}
