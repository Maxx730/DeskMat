# Plan: Media Control Widget — Settings Integration + Album Art Toggle

## Goal

Two things in one PR:

1. **Settings entry** — add a `showMediaControlWidget` toggle to `WidgetsSettingsTab`, Pro-gated and following the exact pattern every other widget uses.
2. **Album art option** — add a `mediaControlShowAlbumArt` toggle that, when on, shows decoded album art in the widget in a side-by-side layout; when off, keeps the current centered title/artist layout.

Both settings persist via `@AppStorage` / `UserDefaults` and survive app restarts.

---

## Current state

| File | Relevant state |
|---|---|
| `MediaControlWidget.swift` | Fully implemented. Hover shows controls, no hover shows title/artist centered. No album art. Always rendered unconditionally. |
| `ContentView.swift:104` | `MediaControlWidget()` with a comment "Phase 2 temporary wiring — replaced with @AppStorage gate in Phase 4". Not Pro-gated. |
| `SettingsView.swift` | No entry for MediaControl in `WidgetsSettingsTab`. |
| `Strings.swift:297` | `MediaControl.settingsLabel = "Media Control Widget"` already exists. |
| `NowPlayingInfo.swift` | `artworkData: Data?` already stored on the model. |

---

## Phase 1 — Settings strings

**Scope:** `Core/Strings.swift`

Add a `showAlbumArt` label inside the existing `MediaControl` enum:

```swift
enum MediaControl {
    static let widgetLabel    = "Media"
    static let nothingPlaying = "Nothing Playing"
    static let settingsLabel  = "Media Control Widget"
    static let showAlbumArt   = "Show Album Art"   // ← add this
}
```

No other changes to strings needed — `settingsLabel` already exists.

---

## Phase 2 — Widget: album art layout

**Scope:** `DeskMat/Widgets/MediaControl/MediaControlWidget.swift`

Add the `@AppStorage` key and rework `trackView` so it branches on the preference.

### 2a — New state properties

```swift
@AppStorage("mediaControlShowAlbumArt") private var showAlbumArt = true
@State private var artworkImage: Image? = nil
@State private var artworkSourceData: Data? = nil
```

### 2b — Artwork decoding

Decode off the main thread and cache so the widget doesn't re-decode on every render:

```swift
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

Clear cached artwork when nothing is playing:

```swift
.onChange(of: media.nowPlaying) { _, new in
    if new == nil { artworkImage = nil; artworkSourceData = nil }
}
```

### 2c — Branched `trackView`

Replace the current `trackView` body with a branch on `showAlbumArt`. Both branches keep the existing hover-fade mechanic (info fades out, controls fade in).

**Album art ON — side-by-side layout:**

```
┌──────────────────────────────────────────┐
│  [44×44 art]  Title           ⏮  ⏸  ⏭ │
│               Artist                      │
└──────────────────────────────────────────┘
```

- Left: 44×44 rounded art (or white.opacity(0.1) placeholder when decoding/absent)
- Right: title + artist stack
- On hover: art stays visible, text fades out, controls fade in over the right side

**Album art OFF — current centered layout (no changes needed to this path):**

The existing implementation already handles this case — centered title/artist with hover controls. No layout change when art is off.

Full implementation:

```swift
private func trackView(_ track: NowPlayingInfo) -> some View {
    Group {
        if showAlbumArt {
            artTrackView(track)
        } else {
            centeredTrackView(track)
        }
    }
    .animation(.easeInOut(duration: 0.18), value: isHovering)
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
    .onChange(of: media.nowPlaying) { _, new in
        if new == nil { artworkImage = nil; artworkSourceData = nil }
    }
}

private func artTrackView(_ track: NowPlayingInfo) -> some View {
    HStack(spacing: 8) {
        // Album art — always visible, does not fade
        Group {
            if let art = artworkImage {
                art.resizable().scaledToFill()
            } else {
                Color.white.opacity(0.1)
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 6))

        // Info / controls — hover fades between the two
        ZStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title.isEmpty ? "Unknown" : track.title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(track.artist.isEmpty ? track.album : track.artist)
                    .font(.system(size: 8))
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(isHovering ? 0 : 1)

            HStack(spacing: 14) {
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
    }
    .padding(.horizontal, 8)
}
```

`centeredTrackView` is the existing `trackView` implementation, extracted and renamed. No logic changes.

**Deliverable:** Widget shows album art (with a fallback placeholder) when `showAlbumArt` is true, and retains the current centered layout when false. Hover interaction works in both modes.

---

## Phase 3 — ContentView wiring and SettingsView entry

### 3a — `App/ContentView.swift`

Add `@AppStorage` alongside the other widget properties:

```swift
@AppStorage("showMediaControlWidget") private var showMediaControlWidget = false
```

Replace the temporary unconditional wiring (line 104) with a Pro-gated conditional:

```swift
// Remove:
// Phase 2 temporary wiring — replaced with @AppStorage gate in Phase 4
MediaControlWidget()

// Add:
if entitlements.isPro && showMediaControlWidget {
    MediaControlWidget()
}
```

Update `anyWidgetVisible` to include the new key (follow the existing pattern for the other Pro widgets):

```swift
showMediaControlWidget ||
```

### 3b — `Settings/SettingsView.swift`

Add two properties to `WidgetsSettingsTab`:

```swift
@AppStorage("showMediaControlWidget")    private var showMediaControlWidget = false
@AppStorage("mediaControlShowAlbumArt")  private var mediaControlShowAlbumArt = true
```

Add a new section following the pattern of every other widget toggle (place it after the Eve widget section, before Web Frame):

```swift
Section {
    Toggle(isOn: $showMediaControlWidget) {
        proLabel(Strings.MediaControl.settingsLabel, isPro: license.isPro)
    }
    .disabled(!license.isPro)

    if showMediaControlWidget && license.isPro {
        Toggle(Strings.MediaControl.showAlbumArt, isOn: $mediaControlShowAlbumArt)
    }
}
```

Add to `resetToDefaults()`:

```swift
ud.set(false, forKey: "showMediaControlWidget")
ud.set(true,  forKey: "mediaControlShowAlbumArt")
```

Note: album art defaults to `true` on reset (enabled is the richer default experience).

**Deliverable:** Widget is Pro-gated and toggleable from Settings. "Show Album Art" sub-toggle appears when the widget is enabled. Both settings survive app restarts.

---

## Files changed

| File | Phase | Change |
|---|---|---|
| `Core/Strings.swift` | 1 | Add `MediaControl.showAlbumArt` label |
| `Widgets/MediaControl/MediaControlWidget.swift` | 2 | Add art decode state, branch `trackView` into `artTrackView` / `centeredTrackView` |
| `App/ContentView.swift` | 3 | Add `@AppStorage`, Pro-gate widget, update `anyWidgetVisible` |
| `Settings/SettingsView.swift` | 3 | Add toggle + album art sub-toggle, reset defaults |

---

## Acceptance criteria

- [ ] Widget does not render when `showMediaControlWidget` is false or user is not Pro
- [ ] Settings toggle shows/hides the widget without restart
- [ ] "Show Album Art" sub-toggle only appears when the widget is enabled and user is Pro
- [ ] Album art on: decoded art displays; falls back to placeholder when absent or decoding
- [ ] Album art off: existing centered title/artist layout unchanged
- [ ] Hover interaction (fade info → show controls) works in both layout modes
- [ ] Artwork decodes on a background thread; no jank when track changes
- [ ] Same art data doesn't trigger a re-decode on unrelated state updates
- [ ] Reset to defaults sets `showMediaControlWidget = false`, `mediaControlShowAlbumArt = true`
