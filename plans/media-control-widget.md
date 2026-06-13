# DeskMat — Media Control Widget Plan

A 2-cell Pro widget that shows the system-wide Now Playing track and lets the
user control playback (play/pause, previous, next) without leaving the dock.
Built on `MediaRemote.framework` (private, loaded dynamically at runtime).
Zero user-facing permission prompts required.

---

## File layout

```
DeskMat/Widgets/MediaControl/
  MediaControlWidget.swift     — main SwiftUI widget body (cellCount = 2)
  NowPlayingInfo.swift         — value type: track data + progress interpolation

DeskMat/Services/
  MediaRemoteService.swift     — dynamic framework loader, @Observable state,
                                  now-playing reads, command dispatch, notifications
```

Four touch-points in existing files:

| File | Change |
|---|---|
| `Core/AppEnums.swift` | `MediaCommand` enum |
| `Core/Strings.swift` | `MediaControl` namespace |
| `App/ContentView.swift` | `@AppStorage("showMediaControlWidget")`, widget instance, `anyWidgetVisible` |
| `App/DeskMatApp.swift` | instantiate `MediaRemoteService`, inject via `.environment()` |
| `Settings/SettingsView.swift` | `WidgetsSettingsTab` entry (toggle) |

`MediaRemoteService` must live in `AppDelegate` (like `SystemMonitorService`) so
only one instance registers for system notifications. It is injected into the
view tree via `.environment()` and consumed in `MediaControlWidget`.

---

## Phase 1 — MediaRemote service and data model

Goal: load the private framework at runtime, read Now Playing info, and send
playback commands. No UI yet — only the service and its supporting types.

### 1a — `AppEnums.swift`: add `MediaCommand`

```swift
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
}
```

### 1b — `NowPlayingInfo.swift`

Value type carrying a single snapshot from `MRMediaRemoteGetNowPlayingInfo`.
Provides live position interpolation without polling MediaRemote every frame.

```swift
import Foundation

struct NowPlayingInfo: Equatable {
    let title:       String
    let artist:      String
    let album:       String
    let artworkData: Data?           // raw JPEG/PNG bytes; nil when unavailable
    let duration:    TimeInterval    // 0 when unknown (e.g. radio stream)
    let playbackRate: Double         // 0 = paused, 1 = playing

    // Position snapshot — taken at fetch time, not updated live by the framework
    let elapsedTime:      TimeInterval
    let snapshotDate:     Date

    // Derived: current position interpolated from the snapshot + wall clock
    var currentPosition: TimeInterval {
        guard playbackRate > 0 else { return elapsedTime }
        return elapsedTime + Date.now.timeIntervalSince(snapshotDate) * playbackRate
    }

    // Normalised 0–1 progress for the progress bar; safe when duration == 0
    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(currentPosition / duration, 0), 1)
    }

    var isPlaying: Bool { playbackRate > 0 }

    // Formatted strings for the time labels (e.g. "2:14")
    static func format(_ t: TimeInterval) -> String {
        guard t.isFinite && t >= 0 else { return "0:00" }
        let s = Int(t)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
```

### 1c — `MediaRemoteService.swift`

`@Observable` class that owns the CFBundle reference, exposes state, and fires
commands. All heavy work runs on a background queue; state mutations hop back to
`@MainActor`.

```swift
import Foundation
import AppKit

@Observable @MainActor
final class MediaRemoteService {

    // MARK: - Public state (read by the widget)
    private(set) var nowPlaying: NowPlayingInfo? = nil
    private(set) var appName: String? = nil      // e.g. "Spotify", "Music"

    // MARK: - Private MediaRemote function-pointer types
    private typealias GetNowPlayingInfo =
        @convention(c) (DispatchQueue, @escaping ([String: Any]) -> Void) -> Void
    private typealias SendCommand =
        @convention(c) (Int, AnyObject?) -> Bool
    private typealias GetAppID =
        @convention(c) (DispatchQueue, @escaping (String?) -> Void) -> Void
    private typealias RegisterNotifications =
        @convention(c) (DispatchQueue) -> Void

    private var mrBundle: CFBundle?
    private var notificationToken: Any?

    init() {
        loadBundle()
        registerForNotifications()
        fetch()
    }

    // MARK: - Framework loading

    private func loadBundle() {
        let url = URL(fileURLWithPath:
            "/System/Library/PrivateFrameworks/MediaRemote.framework")
        mrBundle = CFBundleCreate(kCFAllocatorDefault, url as CFURL)
    }

    // MARK: - Reading state

    func fetch() {
        guard let bundle = mrBundle,
              let ptr = CFBundleGetFunctionPointerForName(
                  bundle, "MRMediaRemoteGetNowPlayingInfo" as CFString)
        else { return }
        let fn = unsafeBitCast(ptr, to: GetNowPlayingInfo.self)
        fn(.global(qos: .userInitiated)) { [weak self] info in
            let snapshot = Self.parse(info)
            Task { @MainActor [weak self] in
                self?.nowPlaying = snapshot
            }
        }
        fetchAppName()
    }

    private func fetchAppName() {
        guard let bundle = mrBundle,
              let ptr = CFBundleGetFunctionPointerForName(
                  bundle, "MRMediaRemoteGetNowPlayingApplicationDisplayID" as CFString)
        else { return }
        let fn = unsafeBitCast(ptr, to: GetAppID.self)
        fn(.global()) { [weak self] bundleID in
            guard let bundleID else { return }
            let name = NSRunningApplication.runningApplications(
                withBundleIdentifier: bundleID
            ).first?.localizedName
            Task { @MainActor [weak self] in self?.appName = name }
        }
    }

    // MARK: - Commands

    func send(_ command: MediaCommand) {
        guard let bundle = mrBundle,
              let ptr = CFBundleGetFunctionPointerForName(
                  bundle, "MRMediaRemoteSendCommand" as CFString)
        else { return }
        let fn = unsafeBitCast(ptr, to: SendCommand.self)
        _ = fn(command.rawValue, nil)
        // Re-fetch after a short delay so the widget reflects the new state
        Task {
            try? await Task.sleep(for: .milliseconds(200))
            fetch()
        }
    }

    // MARK: - Notifications

    private func registerForNotifications() {
        // Prefer the framework's own registration function when available
        if let bundle = mrBundle,
           let ptr = CFBundleGetFunctionPointerForName(
               bundle, "MRMediaRemoteRegisterForNowPlayingNotifications" as CFString) {
            let fn = unsafeBitCast(ptr, to: RegisterNotifications.self)
            fn(.main)
        }
        // Observe the distributed notification MediaRemote posts after registration
        notificationToken = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("kMRMediaRemoteNowPlayingInfoDidChange"),
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.fetch()
        }
    }

    deinit {
        if let token = notificationToken {
            DistributedNotificationCenter.default().removeObserver(token)
        }
    }

    // MARK: - Parsing

    private static func parse(_ info: [String: Any]) -> NowPlayingInfo? {
        // Return nil when the dict is empty (nothing playing)
        guard !info.isEmpty else { return nil }
        return NowPlayingInfo(
            title:        info["kMRMediaRemoteNowPlayingInfoTitle"]       as? String ?? "",
            artist:       info["kMRMediaRemoteNowPlayingInfoArtist"]      as? String ?? "",
            album:        info["kMRMediaRemoteNowPlayingInfoAlbum"]       as? String ?? "",
            artworkData:  info["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data,
            duration:     info["kMRMediaRemoteNowPlayingInfoDuration"]    as? TimeInterval ?? 0,
            playbackRate: info["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? Double ?? 0,
            elapsedTime:  info["kMRMediaRemoteNowPlayingInfoElapsedTime"] as? TimeInterval ?? 0,
            snapshotDate: .now
        )
    }
}
```

### 1d — Wire service into `DeskMatApp.swift`

```swift
// In AppDelegate — alongside systemMonitor, windowState, etc.:
let mediaRemote = MediaRemoteService()

// In setupPanel() — add to ContentView environment:
.environment(mediaRemote)

// In applicationDidFinishLaunching — no extra call needed;
// MediaRemoteService.init() starts the fetch and registers notifications.
```

**Deliverable:** `MediaRemoteService` loads, reads the current track on launch,
and re-fetches on every Now Playing change notification. Commands can be sent.
No UI yet — verify with breakpoints or `print` statements.

---

## Phase 2 — Skeleton widget

Goal: a visible widget that proves the service wires into SwiftUI correctly.
Shows art placeholder, title, artist, and a working play/pause button.
No progress bar or prev/next controls yet.

### 2a — `Strings.swift`: add `MediaControl` namespace

```swift
enum MediaControl {
    static let widgetLabel   = "Media"
    static let nothingPlaying = "Nothing Playing"
    static let settingsLabel = "Show Media Control Widget"
}
```

### 2b — `MediaControlWidget.swift` (skeleton)

```swift
import SwiftUI

struct MediaControlWidget: View {
    static let cellCount = 2

    @Environment(MediaRemoteService.self) private var media
    @AppStorage("showLabels") private var showLabels = true

    var body: some View {
        VStack(spacing: 10) {
            DockWidget(cells: Self.cellCount, isLoading: false, onRefresh: nil) {
                if let track = media.nowPlaying {
                    trackView(track)
                } else {
                    nothingPlayingView
                }
            }
            if showLabels {
                Text(Strings.MediaControl.widgetLabel)
                    .font(.caption2)
                    .lineLimit(1)
                    .frame(width: DockWidget<EmptyView>.width(for: Self.cellCount))
            }
        }
    }

    // MARK: - Track view (Phase 2: art placeholder + title + play/pause)

    private func trackView(_ track: NowPlayingInfo) -> some View {
        HStack(spacing: 6) {
            // Art placeholder — replaced with decoded image in Phase 3
            RoundedRectangle(cornerRadius: 6)
                .fill(.white.opacity(0.15))
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(track.title.isEmpty ? "Unknown" : track.title)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(track.artist.isEmpty ? track.album : track.artist)
                    .font(.system(size: 8))
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(1)
            }

            Spacer()

            Button {
                media.send(.togglePlayPause)
            } label: {
                Image(systemName: track.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
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
```

### 2c — Temporary `ContentView.swift` wiring

Add `MediaControlWidget()` unconditionally (no Pro gate yet) alongside the
other widgets to test it during development. Replace with proper gating in
Phase 4.

**Deliverable:** Widget is visible in the dock, shows current track title and
artist, play/pause button works, "Nothing Playing" state shows when no app is
active. Album art is a grey placeholder.

---

## Phase 3 — Full UI: artwork, prev/next, progress bar

Goal: complete the visual design with decoded album art, all three transport
controls, and a live progress bar driven by local interpolation.

### 3a — Artwork decoding

Artwork data is often several hundred KB of JPEG. Decode off the main thread
and cache the result so the widget doesn't re-decode on every SwiftUI render.

```swift
// In MediaControlWidget:
@State private var artworkImage: Image? = nil
@State private var artworkSourceData: Data? = nil  // tracks which data is cached

// Decode when nowPlaying changes:
.onChange(of: media.nowPlaying?.artworkData) { _, newData in
    guard newData != artworkSourceData else { return }
    artworkSourceData = newData
    artworkImage = nil
    guard let data = newData else { return }
    Task.detached(priority: .userInitiated) {
        guard let ns = NSImage(data: data) else { return }
        let img = Image(nsImage: ns)
        await MainActor.run { artworkImage = img }
    }
}
```

Replace the grey placeholder rectangle in `trackView` with:

```swift
Group {
    if let art = artworkImage {
        art.resizable().scaledToFill()
    } else {
        Color.white.opacity(0.1)
    }
}
.frame(width: 44, height: 44)
.clipShape(RoundedRectangle(cornerRadius: 6))
```

### 3b — Previous and next buttons

Add ⏮ and ⏭ alongside the play/pause button:

```swift
HStack(spacing: 4) {
    Button { media.send(.previousTrack) } label: {
        Image(systemName: "backward.fill")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.white.opacity(0.8))
            .frame(width: 20, height: 20)
    }
    .buttonStyle(.plain)

    Button { media.send(.togglePlayPause) } label: {
        Image(systemName: track.isPlaying ? "pause.fill" : "play.fill")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: 24, height: 24)
    }
    .buttonStyle(.plain)

    Button { media.send(.nextTrack) } label: {
        Image(systemName: "forward.fill")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.white.opacity(0.8))
            .frame(width: 20, height: 20)
    }
    .buttonStyle(.plain)
}
```

### 3c — Progress bar with live interpolation

The elapsed time from MediaRemote is a snapshot taken at the moment of the
last fetch, not a live stream. A `TimelineView` or a local `@State` timer
drives the bar forward between fetches.

```swift
// In MediaControlWidget:
@State private var displayProgress: Double = 0

// Thin bar at the bottom of the DockWidget content area:
GeometryReader { geo in
    ZStack(alignment: .leading) {
        Capsule().fill(.white.opacity(0.15)).frame(height: 2)
        Capsule()
            .fill(.white.opacity(0.6))
            .frame(width: geo.size.width * displayProgress, height: 2)
    }
}
.frame(height: 2)
.padding(.horizontal, 8)

// Timer that advances the bar each second while playing:
.task(id: media.nowPlaying?.isPlaying) {
    while !Task.isCancelled {
        displayProgress = media.nowPlaying?.progress ?? 0
        try? await Task.sleep(for: .seconds(1))
    }
}
// Snap to new value whenever the snapshot updates (e.g. user seeks):
.onChange(of: media.nowPlaying?.elapsedTime) {
    displayProgress = media.nowPlaying?.progress ?? 0
}
```

Time labels (`2:14 / 3:42`) can be placed as a small HStack below the track
info if space allows, or omitted for the compact layout.

### 3d — Full layout composition

```
┌──────────────────────────────────────────────────────────┐  128 × 64pt
│  [44×44 art]   Track Title              ⏮   ⏸   ⏭    │
│                Artist                                     │
│  ────────────────────────────────────── 2:14 / 3:42      │  ← 2pt bar
└──────────────────────────────────────────────────────────┘
```

The 64pt height is tight. If the time labels make the layout feel crowded,
omit them and show only the progress bar fill.

**Deliverable:** Widget shows decoded album art, all three transport controls
work, and the progress bar advances smoothly. Seeking in the player app causes
the bar to snap to the new position on the next notification.

---

## Phase 4 — Settings integration, ContentView wiring, Pro gate

Goal: wire the widget into the official settings and content flows, apply Pro
gating, and clean up the temporary hardcoding from Phase 2.

### 4a — `ContentView.swift`

```swift
// New @AppStorage alongside the others:
@AppStorage("showMediaControlWidget") private var showMediaControlWidget = false

// After the existing Pro-gated widgets:
if entitlements.isPro && showMediaControlWidget {
    MediaControlWidget()
}

// Update anyWidgetVisible:
private var anyWidgetVisible: Bool {
    showTestWidget || (entitlements.isPro && (
        showWeatherWidget || showImageWidget || showLEDBoard ||
        showClockWidget || showSystemWidget || showEveWidget ||
        showWebFrameWidget || showMediaControlWidget
    ))
}
```

Remove the temporary unconditional `MediaControlWidget()` added in Phase 2.

### 4b — `SettingsView.swift`

Add to `WidgetsSettingsTab`:

```swift
@AppStorage("showMediaControlWidget") private var showMediaControlWidget = false

// New section (after other widget toggles):
Section {
    Toggle(isOn: $showMediaControlWidget) {
        proLabel(Strings.MediaControl.settingsLabel, isPro: license.isPro)
    }
    .disabled(!license.isPro)
}
```

The media widget has no per-instance settings (no URL to configure, no
refresh rate to choose) so a single toggle is sufficient.

### 4c — Reset to defaults in `SettingsView.swift`

Add to `resetDefaults()`:

```swift
ud.set(false, forKey: "showMediaControlWidget")
```

### 4d — `DeskMatApp.swift`: inject `MediaRemoteService`

```swift
// In AppDelegate, alongside other services:
let mediaRemote = MediaRemoteService()

// In setupPanel() — add to ContentView environments:
let content = ContentView()
    .environment(entitlements)
    .environment(systemMonitor)
    .environment(windowState)
    .environment(dragCoordinator)
    .environment(eveService)
    .environment(mediaRemote)   // ← add this
```

**Deliverable:** Widget is Pro-gated, togglable from Settings, and clean in
ContentView. Service is created once at app launch and shared across any
future widget instances.

---

## Edge cases to handle

| Case | Handling |
|---|---|
| Nothing playing | Show music note icon + "Nothing Playing" label |
| Track with no title | Show "Unknown" |
| Track with no artist | Fall back to album name |
| No artwork | Show grey rounded rectangle placeholder |
| Duration = 0 (radio stream) | Hide progress bar; show no time labels |
| MediaRemote framework missing | All function pointer lookups return nil safely; widget shows nothing-playing state permanently |
| App switches to a new track rapidly | `onChange(of: artworkData)` skips re-decode if data hasn't changed (same track skipped/replayed) |
| User seeks in the player app | `kMRMediaRemoteNowPlayingInfoDidChange` fires → `fetch()` → new snapshot → progress bar snaps to correct position |

---

## Acceptance criteria

- [ ] Widget renders at 2-cell width (128 × 64 pt) without visual overflow
- [ ] "Nothing Playing" placeholder shows when no media app has a session
- [ ] Track title and artist display correctly for Apple Music, Spotify, and browser media
- [ ] Album art decodes and displays; falls back to placeholder when absent
- [ ] Play/pause button toggles correctly and reflects current playback state
- [ ] Previous and next buttons skip tracks in the active player
- [ ] Progress bar advances in real time while playing; stays still while paused
- [ ] Seeking in the player app causes the bar to snap to the correct position within ~200ms
- [ ] Widget is Pro-gated: does not appear without `license.isPro`
- [ ] Settings toggle shows/hides the widget
- [ ] `MediaRemoteService` is instantiated exactly once (not once per widget render)
- [ ] App does not crash when MediaRemote framework is unavailable (all function pointer guards fire)
- [ ] No Accessibility permission prompt is triggered at any point
