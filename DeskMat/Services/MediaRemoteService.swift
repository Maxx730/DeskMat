import Foundation
import AppKit

// Apple Music and Spotify both broadcast distributed notifications when
// playback state changes — no TCC permissions required. We subscribe to
// those. MRMediaRemoteSendCommand is kept for playback control.

@Observable @MainActor
final class MediaRemoteService {

    // MARK: - Public state

    private(set) var nowPlaying: NowPlayingInfo? = nil
    private(set) var appName: String? = nil

    // MARK: - Private

    private typealias SendCommand = @convention(c) (Int, AnyObject?) -> Bool
    private var mrBundle: CFBundle?
    nonisolated(unsafe) private var tokens: [Any] = []

    // MARK: - Init

    init() {
        loadBundle()
        registerForNotifications()
    }

    deinit {
        let dc = DistributedNotificationCenter.default()
        tokens.forEach { dc.removeObserver($0) }
    }

    // MARK: - Framework loading (send commands only)

    private func loadBundle() {
        let url = URL(fileURLWithPath:
            "/System/Library/PrivateFrameworks/MediaRemote.framework")
        mrBundle = CFBundleCreate(kCFAllocatorDefault, url as CFURL)
    }

    // MARK: - Distributed notifications

    private func registerForNotifications() {
        let dc = DistributedNotificationCenter.default()

        // Apple Music posts this on every track change and play/pause toggle.
        // userInfo keys: Name, Artist, Album, Total Time, Elapsed Time, Player State
        tokens.append(dc.addObserver(
            forName: NSNotification.Name("com.apple.Music.playerInfo"),
            object: nil, queue: .main
        ) { [weak self] note in
            MainActor.assumeIsolated {
                self?.handleMusicNotification(note.userInfo)
                self?.appName = "Music"
            }
        })

        // Spotify posts this on every playback state change.
        // userInfo keys: Name, Artist, Album, Duration (ms), Playback Position, Player State
        tokens.append(dc.addObserver(
            forName: NSNotification.Name("com.spotify.client.PlaybackStateChanged"),
            object: nil, queue: .main
        ) { [weak self] note in
            MainActor.assumeIsolated {
                self?.handleSpotifyNotification(note.userInfo)
                self?.appName = "Spotify"
            }
        })

        // Clear state when the source app quits
        let ws = NSWorkspace.shared.notificationCenter
        let musicBundleID   = "com.apple.Music"
        let spotifyBundleID = "com.spotify.client"
        tokens.append(ws.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            let id = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            guard id == musicBundleID || id == spotifyBundleID else { return }
            MainActor.assumeIsolated { self?.nowPlaying = nil }
        })
    }

    // MARK: - Notification handlers

    private func handleMusicNotification(_ info: [AnyHashable: Any]?) {
        guard let info else { nowPlaying = nil; return }
        let state  = info["Player State"] as? String ?? ""
        let title  = info["Name"]         as? String ?? ""
        let artist = info["Artist"]       as? String ?? ""
        guard (state == "Playing" || state == "Paused"), !title.isEmpty || !artist.isEmpty else {
            nowPlaying = nil
            return
        }
        nowPlaying = NowPlayingInfo(
            title:        title,
            artist:       artist,
            album:        info["Album"] as? String ?? "",
            artworkData:  nil,
            duration:     info["Total Time"]    as? TimeInterval ?? 0,
            playbackRate: state == "Playing" ? 1.0 : 0,
            elapsedTime:  info["Elapsed Time"]  as? TimeInterval ?? 0,
            snapshotDate: .now
        )
    }

    private func handleSpotifyNotification(_ info: [AnyHashable: Any]?) {
        guard let info else { nowPlaying = nil; return }
        let state  = info["Player State"] as? String ?? ""
        let title  = info["Name"]         as? String ?? ""
        let artist = info["Artist"]       as? String ?? ""
        guard (state == "playing" || state == "paused"), !title.isEmpty || !artist.isEmpty else {
            nowPlaying = nil
            return
        }
        nowPlaying = NowPlayingInfo(
            title:        title,
            artist:       artist,
            album:        info["Album"]            as? String ?? "",
            artworkData:  nil,
            duration:     (info["Duration"] as? TimeInterval ?? 0) / 1000,
            playbackRate: state == "playing" ? 1.0 : 0,
            elapsedTime:  info["Playback Position"] as? TimeInterval ?? 0,
            snapshotDate: .now
        )
    }

    // MARK: - Send commands

    func send(_ command: MediaCommand) {
        if let bundle = mrBundle,
           let ptr = CFBundleGetFunctionPointerForName(
               bundle, "MRMediaRemoteSendCommand" as CFString) {
            let fn = unsafeBitCast(ptr, to: SendCommand.self)
            _ = fn(command.rawValue, nil)
        }
    }

    // Kept for widget compatibility — no-op since state comes from notifications
    func fetch() {}
}
