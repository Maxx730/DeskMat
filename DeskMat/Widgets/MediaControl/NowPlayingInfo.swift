import Foundation

struct NowPlayingInfo: Equatable {
    let title:        String
    let artist:       String
    let album:        String
    let artworkData:  Data?
    let duration:     TimeInterval
    let playbackRate: Double

    // Snapshot taken at fetch time — not updated live by the framework
    let elapsedTime:  TimeInterval
    let snapshotDate: Date

    // Current position interpolated from the snapshot + wall clock
    var currentPosition: TimeInterval {
        guard playbackRate > 0 else { return elapsedTime }
        return elapsedTime + Date.now.timeIntervalSince(snapshotDate) * playbackRate
    }

    // Normalised 0–1 progress for the progress bar
    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(currentPosition / duration, 0), 1)
    }

    var isPlaying: Bool { playbackRate > 0 }

    static func format(_ t: TimeInterval) -> String {
        guard t.isFinite && t >= 0 else { return "0:00" }
        let s = Int(t)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
