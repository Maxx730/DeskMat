# Exploration: Media Control Widget

## Overview

A widget that shows what's currently playing system-wide and lets the user control playback (play/pause, skip, previous) without switching apps. On macOS the primary mechanism is `MediaRemote.framework` — the same private framework that powers the Control Center media tile and the Touch Bar media controls. There are also public APIs, but they cover different ground.

---

## APIs Available

### 1. MediaRemote.framework (Private — Primary Option)

The most capable option. Located at `/System/Library/PrivateFrameworks/MediaRemote.framework`. Because it's a private framework, it cannot be linked against directly — it must be loaded at runtime via `CFBundleCreate` and function pointers cast from `CFBundleGetFunctionPointerForName`.

**What you can read:**

| Info Key | Type | Value |
|---|---|---|
| `kMRMediaRemoteNowPlayingInfoTitle` | `String` | Track name |
| `kMRMediaRemoteNowPlayingInfoArtist` | `String` | Artist name |
| `kMRMediaRemoteNowPlayingInfoAlbum` | `String` | Album name |
| `kMRMediaRemoteNowPlayingInfoDuration` | `Double` | Total duration in seconds |
| `kMRMediaRemoteNowPlayingInfoElapsedTime` | `Double` | Position at last update (snapshot) |
| `kMRMediaRemoteNowPlayingInfoPlaybackRate` | `Double` | 0.0 = paused, 1.0 = playing, 2.0 = fast-forward |
| `kMRMediaRemoteNowPlayingInfoArtworkData` | `Data` | Raw image bytes (typically JPEG/PNG) |
| `kMRMediaRemoteNowPlayingInfoArtworkMIMEType` | `String` | MIME type of artwork data |
| `kMRMediaRemoteNowPlayingInfoShuffleMode` | `Int` | 0 = off, 1 = songs, 2 = albums |
| `kMRMediaRemoteNowPlayingInfoRepeatMode` | `Int` | 0 = off, 1 = one, 2 = all |
| `kMRMediaRemoteNowPlayingInfoQueueIndex` | `Int` | Position in queue |
| `kMRMediaRemoteNowPlayingInfoTotalQueueCount` | `Int` | Total queue length |

**Reading now playing info:**

```swift
typealias GetNowPlayingInfo = @convention(c) (DispatchQueue, @escaping ([String: Any]) -> Void) -> Void

func loadNowPlayingInfo(completion: @escaping ([String: Any]) -> Void) {
    let url = URL(fileURLWithPath: "/System/Library/PrivateFrameworks/MediaRemote.framework")
    guard let bundle = CFBundleCreate(kCFAllocatorDefault, url as CFURL),
          let ptr = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteGetNowPlayingInfo" as CFString)
    else { return }
    let fn = unsafeBitCast(ptr, to: GetNowPlayingInfo.self)
    fn(.main, completion)
}
```

**Sending playback commands:**

```swift
typealias SendCommand = @convention(c) (Int, AnyObject?) -> Bool

// Commands — these match the undocumented MRMediaRemoteCommand enum
enum MediaCommand: Int {
    case play            = 0
    case pause           = 1
    case togglePlayPause = 2
    case stop            = 3
    case nextTrack       = 4
    case previousTrack   = 5
    case beginFastForward  = 8
    case endFastForward    = 9
    case beginRewind       = 10
    case endRewind         = 11
    case seekToPlaybackPosition = 45   // requires a context dict with the target position
}
```

```swift
func sendMediaCommand(_ command: MediaCommand) {
    let url = URL(fileURLWithPath: "/System/Library/PrivateFrameworks/MediaRemote.framework")
    guard let bundle = CFBundleCreate(kCFAllocatorDefault, url as CFURL),
          let ptr = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteSendCommand" as CFString)
    else { return }
    let fn = unsafeBitCast(ptr, to: SendCommand.self)
    _ = fn(command.rawValue, nil)
}
```

**Identifying the active player:**

```swift
typealias GetAppDisplayID = @convention(c) (DispatchQueue, @escaping (String?) -> Void) -> Void
// Returns bundle ID of the app currently "owning" the Now Playing session
// e.g. "com.spotify.client", "com.apple.Music", "com.google.Chrome"
```

**Observing changes:**

MediaRemote posts distributed notifications when the Now Playing state changes. These can be observed system-wide without polling:

```swift
typealias RegisterForNotifications = @convention(c) (DispatchQueue) -> Void

// Notification names (post to DistributedNotificationCenter)
// "kMRMediaRemoteNowPlayingInfoDidChange"
// "kMRMediaRemoteNowPlayingApplicationDidChange"
// "kMRMediaRemoteNowPlayingApplicationIsPlayingDidChange"
```

Once registered, changes fire a `DistributedNotificationCenter` notification — no polling loop needed.

---

### 2. MediaPlayer Framework (Public — Limited Use)

`import MediaPlayer` is the App Store-safe public API but its macOS capabilities are narrower than on iOS.

**`MPNowPlayingInfoCenter`** — primarily intended for apps that **publish** their own Now Playing state. On macOS, reading `.nowPlayingInfo` from a third-party app reflects whatever that process last wrote; it does not give access to system-wide playing info the way MediaRemote does.

**`MPRemoteCommandCenter`** — lets your app **receive** remote commands (from Control Center, Bluetooth headsets, etc.). This is the right API if DeskMat itself becomes the media player, but it cannot send commands to other apps.

**Verdict:** The public MediaPlayer framework is the wrong direction for a widget that monitors and controls external apps. MediaRemote is the right tool.

---

### 3. IOKit HID Media Key Simulation

An alternative to MediaRemote for playback control: simulate the physical media keys (F7/F8/F9 or the dedicated Play/Next/Previous keys) by posting HID events via CoreGraphics.

```swift
import IOKit.hidsystem

// NX_KEYTYPE_PLAY = 16, NX_KEYTYPE_NEXT = 17, NX_KEYTYPE_PREVIOUS = 18
func pressMediaKey(_ keyType: Int32) {
    func event(flags: UInt) -> NSEvent? {
        NSEvent.otherEvent(with: .systemDefined, location: .zero,
            modifierFlags: NSEvent.ModifierFlags(rawValue: flags),
            timestamp: 0, windowNumber: 0, context: nil,
            subtype: 8,
            data1: Int((keyType << 16) | (Int32(flags == 0xa00 ? 0xa : 0xb) << 8)),
            data2: -1)
    }
    event(flags: 0xa00)?.cgEvent?.post(tap: .cghidEventTap)
    event(flags: 0xb00)?.cgEvent?.post(tap: .cghidEventTap)
}
```

**Catch:** `CGEvent.post(tap: .cghidEventTap)` requires the app to be granted Accessibility permission by the user (System Settings → Privacy & Security → Accessibility). Without it the calls silently do nothing. This is a user-facing permission prompt that some users may be confused by or decline.

MediaRemote's `MRMediaRemoteSendCommand` does **not** require Accessibility — it talks directly to the media daemon. HID simulation is a fallback approach; MediaRemote is better.

---

### 4. AppleScript (App-Specific)

For named apps — Apple Music, Spotify, Vox — AppleScript can query richer state (full library info, playlist names, rating, loved status) and perform app-specific actions.

```swift
// Requires com.apple.security.automation.apple-events entitlement
let script = NSAppleScript(source: "tell application \"Spotify\" to return current track")
var error: NSDictionary?
let result = script?.executeAndReturnError(&error)
```

**Limitations:**
- Only works for scriptable apps that expose an AppleScript dictionary.
- Requires `com.apple.security.automation.apple-events` entitlement and a user-facing permission prompt for each target app (macOS 10.14+).
- Does not work for browser media (YouTube, SoundCloud in Safari/Chrome).
- Each app has a different dictionary — no unified interface.

This is worthwhile as a supplement (e.g., "loved" button for Apple Music) but not a foundation for a general widget.

---

## What Works Across All Players

Via MediaRemote, these work for any app that publishes a Now Playing session — Apple Music, Spotify, Podcasts, Overcast, YouTube in Safari/Chrome, IINA, VLC, Castro, and more:

| Capability | Available |
|---|---|
| Track title | Yes |
| Artist name | Yes |
| Album name | Yes |
| Album artwork (image data) | Yes |
| Playback state (playing/paused) | Yes |
| Track duration | Yes |
| Current position (snapshot) | Yes — but not live-streaming; needs local interpolation |
| Skip to next | Yes |
| Skip to previous | Yes |
| Play / Pause / Toggle | Yes |
| Seek to position | Yes (command 45 with position context dict) |
| Shuffle / Repeat state | Yes (read-only; toggling is command 6/7) |
| Queue contents | No |
| Volume | No (MediaRemote can't; CoreAudio can set system volume separately) |
| Which app is playing | Yes (bundle ID) |

---

## What You Cannot Do

- **Browse the library** — no access to track lists, albums, artists outside what the active session exposes.
- **Read lyrics** — not in the Now Playing info dict.
- **Queue manipulation** — no MediaRemote API for reordering or adding to queue.
- **Set volume per-app** — CoreAudio can only set system output volume or per-process volume via the undocumented `setVolume:forPID:` path.
- **Control browser media granularly** — you can play/pause a YouTube tab but you can't seek to a position or read the video title reliably (the tab's document title is all that's available).
- **Multiple simultaneous sessions** — MediaRemote tracks one "active" player at a time; you can't independently control two apps.

---

## Position Tracking (Progress Bar)

`kMRMediaRemoteNowPlayingInfoElapsedTime` is a **snapshot** taken at the moment you call `MRMediaRemoteGetNowPlayingInfo` — it doesn't update in real time. To drive a live progress bar, combine it with a local timer:

```swift
// On receiving new info:
var positionAtSnapshot: Double = 0
var snapshotTimestamp: Date = .now
var playbackRate: Double = 0

// To compute current position:
var currentPosition: Double {
    let elapsed = Date.now.timeIntervalSince(snapshotTimestamp)
    return positionAtSnapshot + elapsed * playbackRate
}
```

When the user seeks, MediaRemote fires `kMRMediaRemoteNowPlayingInfoDidChange` and you re-snapshot.

---

## Permissions Required

| Action | Permission Needed |
|---|---|
| Reading Now Playing info | None |
| Observing Now Playing notifications | None |
| Sending play/pause/skip commands via MediaRemote | None |
| Seeking to position via MediaRemote | None |
| Media key simulation via IOKit HID | Accessibility (user prompt) |
| AppleScript control of Music/Spotify | `apple-events` entitlement + per-app user prompt |

MediaRemote read + command is the best path — zero user-facing permission prompts.

---

## App Compatibility Notes

| Player | Now Playing Info | Commands |
|---|---|---|
| Apple Music | Full (title, artist, album, artwork) | Full |
| Spotify | Full on Premium; Free tier may omit artwork/position | Full |
| Podcasts | Full (episode title, show name) | Full |
| IINA / VLC | Full (if Now Playing publishing is enabled in app settings) | Full |
| Safari (YouTube tab) | Title from document, no artwork | Play/pause/skip |
| Chrome / Firefox (YouTube) | Title from document, no artwork | Play/pause (skip unreliable) |
| Overcast / Castro | Full | Full |

---

## Widget Design Sketch

```
┌─────────────────────────────────────────────┐
│  [art]  Track Title                ⏮  ⏸  ⏭ │  ← 2 cells (128 × 64 pt)
│         Artist · Album                       │
│         ────────────────── 2:14 / 3:42      │
└─────────────────────────────────────────────┘
```

- **cellCount = 2** — 128 × 64 pt canvas, same as Weather/WebFrame.
- Album art: small square (~40 × 40 pt), rounded corners, decoded from `kMRMediaRemoteNowPlayingInfoArtworkData`.
- Track + artist: truncated single-line labels, system font.
- Progress bar: thin line at the bottom, driven by local timer interpolation.
- Controls: play/pause (toggles icon), previous, next — shown always or on hover.
- "Nothing playing" state: muted icon + placeholder text.
- Refresh strategy: observe distributed notifications for changes, no polling loop.

---

## Risks and Trade-offs

| Risk | Severity | Mitigation |
|---|---|---|
| MediaRemote API changes between macOS versions | Low-Medium | Load dynamically so a nil function pointer causes a graceful fallback, not a crash |
| App Store rejection for private framework usage | Medium if submitting | DeskMat is direct-distribution; not currently a concern |
| Artwork data can be large (up to several MB for hi-res JPEG) | Low | Decode on a background queue; downscale to widget size before rendering |
| Position interpolation drift on fast-forward/scrub | Low | Re-snapshot on every `NowPlayingInfoDidChange` notification |
| Spotify on Free tier throttles/omits metadata | Low | Show graceful fallback when keys are absent |

---

## Verdict

Fully achievable with no user-facing permissions. The `MediaRemote.framework` dynamic-load pattern is well-established — dozens of macOS menu bar apps (NowPlaying, Sleeve, Noizio, etc.) use exactly this approach. The main engineering concerns are:

1. **Artwork handling** — large images must be decoded off the main thread to avoid frame drops.
2. **Position bar** — needs local interpolation, not a polling loop, to stay smooth.
3. **Nothing-playing state** — needs a clean placeholder since the widget is always visible.
4. **Graceful degradation** — check every function pointer for nil before casting; macOS may move the framework.
