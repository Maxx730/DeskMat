import SwiftUI

struct MediaControlWidget: View {
    static let cellCount = 2

    @Environment(MediaRemoteService.self) private var media
    @AppStorage("showLabels") private var showLabels = true
    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 10) {
            DockWidget(cells: Self.cellCount, backgroundColor: .blue) {
                if let track = media.nowPlaying {
                    trackView(track)
                } else {
                    nothingPlayingView
                }
            }
            .onHover { isHovering = $0 }

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

    private func trackView(_ track: NowPlayingInfo) -> some View {
        ZStack {
            // Info layer — fades out on hover
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
            }.frame(maxWidth: .infinity, alignment: .center)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .opacity(isHovering ? 0 : 1)

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
