import SwiftUI
import CoreImage

struct MediaControlWidget: View {
    static let cellCount = 3

    @Environment(MediaRemoteService.self) private var media
    @AppStorage("showLabels") private var showLabels = true
    @AppStorage("mediaControlShowAlbumArt") private var showAlbumArt = true
    @State private var isHovering = false
    @State private var artworkImage: Image? = nil
    @State private var artworkSourceData: Data? = nil
    @State private var widgetBackground: Color = .blue

    var body: some View {
        VStack(spacing: 10) {
            DockWidget(cells: Self.cellCount, backgroundColor: widgetBackground) {
                if let track = media.nowPlaying {
                    trackView(track)
                } else {
                    nothingPlayingView
                }
            }
            .onHover { isHovering = $0 }
            .onChange(of: media.nowPlaying?.artworkData) { _, newData in
                guard newData != artworkSourceData else { return }
                artworkSourceData = newData
                artworkImage = nil
                guard let data = newData else { return }
                Task.detached(priority: .userInitiated) {
                    guard let ns = NSImage(data: data),
                          let cg = ns.cgImage(forProposedRect: nil, context: nil, hints: nil)
                    else { return }
                    let img = Image(nsImage: ns)
                    let avg = Self.averageColor(from: cg)
                    await MainActor.run {
                        artworkImage = img
                        widgetBackground = avg ?? .blue
                    }
                }
            }
            .onChange(of: media.nowPlaying) { _, new in
                if new == nil {
                    artworkImage = nil
                    artworkSourceData = nil
                    widgetBackground = .blue
                }
            }

            if showLabels {
                Text(Strings.MediaControl.widgetLabel)
                    .font(.caption2)
                    .lineLimit(1)
                    .frame(width: DockWidget<EmptyView>.width(for: Self.cellCount))
                    .truncationMode(.tail)
            }
        }
    }

    // MARK: - Track view

    @ViewBuilder
    private func trackView(_ track: NowPlayingInfo) -> some View {
        if showAlbumArt {
            artTrackView(track)
        } else {
            centeredTrackView(track)
        }
    }

    // MARK: - Art layout

    private func artTrackView(_ track: NowPlayingInfo) -> some View {
        ZStack {
            // Info layer — art + text fade out together on hover
            HStack(spacing: 12) {
                Group {
                    if let art = artworkImage {
                        art.resizable().scaledToFill()
                    } else {
                        Color.white.opacity(0.1)
                    }
                }
                .frame(width: 46, height: 46)
                .clipShape(RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title.isEmpty ? "Unknown" : track.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(track.artist.isEmpty ? track.album : track.artist)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 8)
            .blur(radius: isHovering ? 4 : 0)

            // Controls layer — fades in on hover
            HStack(spacing: 16) {
                Button { media.send(.previousTrack) } label: {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)

                Button { media.send(.togglePlayPause) } label: {
                    Image(systemName: track.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)

                Button { media.send(.nextTrack) } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
            .opacity(isHovering ? 1 : 0)
        }
        .animation(.easeInOut(duration: 0.18), value: isHovering)
    }

    // MARK: - Centered layout

    private func centeredTrackView(_ track: NowPlayingInfo) -> some View {
        ZStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title.isEmpty ? "Unknown" : track.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .center)
                Text(track.artist.isEmpty ? track.album : track.artist)
                    .font(.system(size: 8))
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 10)
            .blur(radius: isHovering ? 4 : 0)

            HStack(spacing: 16) {
                Button { media.send(.previousTrack) } label: {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)

                Button { media.send(.togglePlayPause) } label: {
                    Image(systemName: track.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)

                Button { media.send(.nextTrack) } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
            .opacity(isHovering ? 1 : 0)
        }
        .animation(.easeInOut(duration: 0.18), value: isHovering)
    }

    // MARK: - Average color

    private static func averageColor(from cgImage: CGImage) -> Color? {
        let ci = CIImage(cgImage: cgImage)
        guard let filter = CIFilter(name: "CIAreaAverage",
                                    parameters: [kCIInputImageKey: ci,
                                                 kCIInputExtentKey: CIVector(cgRect: ci.extent)]),
              let output = filter.outputImage
        else { return nil }
        var bitmap = [UInt8](repeating: 0, count: 4)
        CIContext().render(output,
                           toBitmap: &bitmap,
                           rowBytes: 4,
                           bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                           format: .RGBA8,
                           colorSpace: CGColorSpaceCreateDeviceRGB())
        return Color(red: Double(bitmap[0]) / 255,
                     green: Double(bitmap[1]) / 255,
                     blue: Double(bitmap[2]) / 255)
    }

    // MARK: - Nothing playing

    private var nothingPlayingView: some View {
        VStack(spacing: 4) {
            Image(systemName: "music.note")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.3))
            Text(Strings.MediaControl.nothingPlaying)
                .font(.system(size: 8))
                .foregroundStyle(.white.opacity(0.3))
        }
    }
}
