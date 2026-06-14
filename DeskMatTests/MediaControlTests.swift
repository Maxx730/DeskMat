import Testing
import Foundation
@testable import DeskMat

// MARK: - NowPlayingInfo: isPlaying

struct NowPlayingInfoIsPlayingTests {

    @Test func isPlayingWhenRateIsOne() {
        let info = makeInfo(playbackRate: 1.0)
        #expect(info.isPlaying == true)
    }

    @Test func isPlayingWhenRateIsAboveZero() {
        let info = makeInfo(playbackRate: 0.5)
        #expect(info.isPlaying == true)
    }

    @Test func isNotPlayingWhenRateIsZero() {
        let info = makeInfo(playbackRate: 0.0)
        #expect(info.isPlaying == false)
    }
}

// MARK: - NowPlayingInfo: progress

struct NowPlayingInfoProgressTests {

    @Test func progressIsZeroWhenDurationIsZero() {
        let info = makeInfo(duration: 0, playbackRate: 0, elapsedTime: 10)
        #expect(info.progress == 0)
    }

    @Test func progressAtStart() {
        let info = makeInfo(duration: 100, playbackRate: 0, elapsedTime: 0)
        #expect(info.progress == 0)
    }

    @Test func progressAtHalfway() {
        let info = makeInfo(duration: 100, playbackRate: 0, elapsedTime: 50)
        #expect(abs(info.progress - 0.5) < 1e-10)
    }

    @Test func progressAtEnd() {
        let info = makeInfo(duration: 100, playbackRate: 0, elapsedTime: 100)
        #expect(info.progress == 1.0)
    }

    @Test func progressClampedToZeroForNegativeElapsed() {
        let info = makeInfo(duration: 100, playbackRate: 0, elapsedTime: -20)
        #expect(info.progress == 0)
    }

    @Test func progressClampedToOneWhenElapsedExceedsDuration() {
        let info = makeInfo(duration: 100, playbackRate: 0, elapsedTime: 150)
        #expect(info.progress == 1.0)
    }
}

// MARK: - NowPlayingInfo: currentPosition

struct NowPlayingInfoCurrentPositionTests {

    @Test func currentPositionEqualsElapsedWhenPaused() {
        let info = makeInfo(playbackRate: 0, elapsedTime: 42)
        #expect(info.currentPosition == 42)
    }

    @Test func currentPositionAdvancesWhenPlaying() {
        // Snapshot taken 2 seconds ago at elapsed = 10, rate = 1
        let pastDate = Date.now.addingTimeInterval(-2)
        let info = NowPlayingInfo(title: "T", artist: "A", album: "Al",
                                  artworkData: nil, duration: 200,
                                  playbackRate: 1.0, elapsedTime: 10,
                                  snapshotDate: pastDate)
        // currentPosition should be ~12 (10 + 2s elapsed)
        #expect(info.currentPosition > 11.5)
        #expect(info.currentPosition < 12.5)
    }

    @Test func currentPositionDoesNotAdvanceWhenPaused() {
        let pastDate = Date.now.addingTimeInterval(-5)
        let info = NowPlayingInfo(title: "T", artist: "A", album: "Al",
                                  artworkData: nil, duration: 200,
                                  playbackRate: 0, elapsedTime: 30,
                                  snapshotDate: pastDate)
        #expect(info.currentPosition == 30)
    }
}

// MARK: - NowPlayingInfo: format

struct NowPlayingInfoFormatTests {

    @Test func formatZeroSeconds() {
        #expect(NowPlayingInfo.format(0) == "0:00")
    }

    @Test func formatOneMinute() {
        #expect(NowPlayingInfo.format(60) == "1:00")
    }

    @Test func formatOneMinuteThirtySeconds() {
        #expect(NowPlayingInfo.format(90) == "1:30")
    }

    @Test func formatSingleDigitSecondsPadsZero() {
        #expect(NowPlayingInfo.format(65) == "1:05")
    }

    @Test func formatLargeValue() {
        #expect(NowPlayingInfo.format(3661) == "61:01")
    }

    @Test func formatNonFiniteReturnsZero() {
        #expect(NowPlayingInfo.format(.infinity) == "0:00")
        #expect(NowPlayingInfo.format(.nan)      == "0:00")
    }

    @Test func formatNegativeReturnsZero() {
        #expect(NowPlayingInfo.format(-1) == "0:00")
    }
}

// MARK: - NowPlayingInfo: Equatable and mutability

struct NowPlayingInfoEqualityTests {

    @Test func identicalInfosAreEqual() {
        let date = Date(timeIntervalSince1970: 0)
        let a = NowPlayingInfo(title: "Song", artist: "Artist", album: "Album",
                               artworkData: nil, duration: 200,
                               playbackRate: 1.0, elapsedTime: 30,
                               snapshotDate: date)
        let b = NowPlayingInfo(title: "Song", artist: "Artist", album: "Album",
                               artworkData: nil, duration: 200,
                               playbackRate: 1.0, elapsedTime: 30,
                               snapshotDate: date)
        #expect(a == b)
    }

    @Test func differentTitlesAreNotEqual() {
        let date = Date(timeIntervalSince1970: 0)
        let a = NowPlayingInfo(title: "Song A", artist: "Artist", album: "Album",
                               artworkData: nil, duration: 200,
                               playbackRate: 1.0, elapsedTime: 0, snapshotDate: date)
        let b = NowPlayingInfo(title: "Song B", artist: "Artist", album: "Album",
                               artworkData: nil, duration: 200,
                               playbackRate: 1.0, elapsedTime: 0, snapshotDate: date)
        #expect(a != b)
    }

    @Test func differentArtworkDataAreNotEqual() {
        let date = Date(timeIntervalSince1970: 0)
        var a = NowPlayingInfo(title: "Song", artist: "Artist", album: "Album",
                               artworkData: nil, duration: 100,
                               playbackRate: 0, elapsedTime: 0, snapshotDate: date)
        let b = a
        a.artworkData = Data([0xFF, 0x00])
        #expect(a != b)
    }

    @Test func artworkDataIsMutable() {
        var info = makeInfo()
        #expect(info.artworkData == nil)
        let bytes = Data([0x01, 0x02, 0x03])
        info.artworkData = bytes
        #expect(info.artworkData == bytes)
    }

    @Test func clearingArtworkDataToNil() {
        var info = makeInfo(artworkData: Data([0xAB]))
        info.artworkData = nil
        #expect(info.artworkData == nil)
    }
}

// MARK: - MediaControlWidget: cell count

struct MediaControlWidgetCellCountTests {

    @Test func cellCountIsThree() {
        #expect(MediaControlWidget.cellCount == 3)
    }
}

// MARK: - MediaCommand: raw values

struct MediaCommandTests {

    @Test func playRawValue() {
        #expect(MediaCommand.play.rawValue == 0)
    }

    @Test func pauseRawValue() {
        #expect(MediaCommand.pause.rawValue == 1)
    }

    @Test func togglePlayPauseRawValue() {
        #expect(MediaCommand.togglePlayPause.rawValue == 2)
    }

    @Test func stopRawValue() {
        #expect(MediaCommand.stop.rawValue == 3)
    }

    @Test func nextTrackRawValue() {
        #expect(MediaCommand.nextTrack.rawValue == 4)
    }

    @Test func previousTrackRawValue() {
        #expect(MediaCommand.previousTrack.rawValue == 5)
    }

    @Test func beginFastForwardRawValue() {
        #expect(MediaCommand.beginFastForward.rawValue == 8)
    }

    @Test func endFastForwardRawValue() {
        #expect(MediaCommand.endFastForward.rawValue == 9)
    }

    @Test func beginRewindRawValue() {
        #expect(MediaCommand.beginRewind.rawValue == 10)
    }

    @Test func endRewindRawValue() {
        #expect(MediaCommand.endRewind.rawValue == 11)
    }

    @Test func initFromRawValue() {
        #expect(MediaCommand(rawValue: 0)  == .play)
        #expect(MediaCommand(rawValue: 2)  == .togglePlayPause)
        #expect(MediaCommand(rawValue: 4)  == .nextTrack)
        #expect(MediaCommand(rawValue: 5)  == .previousTrack)
        #expect(MediaCommand(rawValue: 99) == nil)
    }
}

// MARK: - Same-track artwork preservation logic

struct SameTrackArtworkPreservationTests {

    @Test func sameTrackPreservesArtwork() {
        // Simulates what the service handlers do: if title+artist match,
        // carry artworkData forward rather than dropping it to nil.
        let existing = NowPlayingInfo(title: "Song", artist: "Artist", album: "Album",
                                      artworkData: Data([0xDE, 0xAD]),
                                      duration: 200, playbackRate: 1.0,
                                      elapsedTime: 30, snapshotDate: .now)
        let incomingTitle  = "Song"
        let incomingArtist = "Artist"
        let sameTrack = existing.title == incomingTitle && existing.artist == incomingArtist
        let carried = sameTrack ? existing.artworkData : nil
        #expect(carried == Data([0xDE, 0xAD]))
    }

    @Test func newTrackDropsArtwork() {
        let existing = NowPlayingInfo(title: "Song", artist: "Artist", album: "Album",
                                      artworkData: Data([0xDE, 0xAD]),
                                      duration: 200, playbackRate: 1.0,
                                      elapsedTime: 30, snapshotDate: .now)
        let incomingTitle  = "Other Song"
        let incomingArtist = "Artist"
        let sameTrack = existing.title == incomingTitle && existing.artist == incomingArtist
        let carried = sameTrack ? existing.artworkData : nil
        #expect(carried == nil)
    }

    @Test func differentArtistDropsArtwork() {
        let existing = NowPlayingInfo(title: "Song", artist: "Artist", album: "Album",
                                      artworkData: Data([0x01]),
                                      duration: 100, playbackRate: 1.0,
                                      elapsedTime: 0, snapshotDate: .now)
        let sameTrack = existing.title == "Song" && existing.artist == "Other Artist"
        let carried = sameTrack ? existing.artworkData : nil
        #expect(carried == nil)
    }
}

// MARK: - Helpers

private func makeInfo(
    title: String = "Title",
    artist: String = "Artist",
    album: String = "Album",
    artworkData: Data? = nil,
    duration: TimeInterval = 100,
    playbackRate: Double = 1.0,
    elapsedTime: TimeInterval = 0,
    snapshotDate: Date = .now
) -> NowPlayingInfo {
    NowPlayingInfo(title: title, artist: artist, album: album,
                   artworkData: artworkData, duration: duration,
                   playbackRate: playbackRate, elapsedTime: elapsedTime,
                   snapshotDate: snapshotDate)
}
