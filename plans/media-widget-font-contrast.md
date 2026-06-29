# Media Widget Font Contrast Fix

## Problem

`MediaControlWidget` extracts the average color from album artwork and uses it as the widget background via `averageColor(from:)`. All text and icon foregrounds are hardcoded to `.white`. When the extracted background is a light or pale color (e.g. artwork with a white or cream palette), white text becomes invisible against it.

## Root Cause

`MediaControlWidget.swift` lines 90, 94, 139, 143 and the control buttons all use `.foregroundStyle(.white)` unconditionally, regardless of whether the background is light or dark.

---

## Phase 1 — Add the contrast helper

Add a static method `contrastingTextColor(for:tintStrength:)` to `MediaControlWidget`. It uses the WCAG relative luminance formula to decide whether white or black is the better base, then blends a small amount of the background color in so the text feels visually connected to the album art palette rather than jarring.

```swift
/// Returns a text color that contrasts with `background` while carrying a slight tint of it.
/// Picks white or black as the base, then blends a small amount of the background color in
/// so the text feels visually connected to the album art palette.
private static func contrastingTextColor(for background: Color, tintStrength: CGFloat = 0.15) -> Color {
    guard let nsColor = NSColor(background).usingColorSpace(.sRGB) else { return .white }
    let r = nsColor.redComponent
    let g = nsColor.greenComponent
    let b = nsColor.blueComponent

    // WCAG relative luminance (linearise each channel first).
    func linearise(_ c: CGFloat) -> CGFloat {
        c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }
    let luminance = 0.2126 * linearise(r) + 0.7152 * linearise(g) + 0.0722 * linearise(b)

    // Base is white on dark backgrounds, black on light ones.
    // Threshold 0.179 ≈ midpoint satisfying a 4.5:1 contrast ratio with both extremes.
    let base: CGFloat = luminance > 0.179 ? 0.0 : 1.0

    // Blend: (1 - tintStrength) of the base + tintStrength of the background channel.
    let mix = 1.0 - tintStrength
    return Color(
        red:   Double(base * mix + r * tintStrength),
        green: Double(base * mix + g * tintStrength),
        blue:  Double(base * mix + b * tintStrength)
    )
}
```

**File:** `DeskMat/Widgets/MediaControl/MediaControlWidget.swift`

---

## Phase 2 — Wire up the state

Add a `@State` variable that holds the computed text color and update it whenever the artwork changes.

**Add the state variable:**

```swift
@State private var textColor: Color = .white
```

**In the `onChange(of: media.nowPlaying?.artworkData)` handler**, right after `widgetBackground` is set, compute the text color:

```swift
widgetBackground = avg ?? .blue
textColor = Self.contrastingTextColor(for: widgetBackground)
```

**In the `onChange(of: media.nowPlaying)` nil branch**, reset both:

```swift
widgetBackground = .blue
textColor = .white
```

**File:** `DeskMat/Widgets/MediaControl/MediaControlWidget.swift`

---

## Phase 3 — Replace hardcoded foreground styles

Swap every `.foregroundStyle(.white)` and `.foregroundStyle(.white.opacity(0.65))` inside `artTrackView` and `centeredTrackView` with the computed `textColor`.

| Location | Old | New |
|---|---|---|
| Track title (both layouts) | `.foregroundStyle(.white)` | `.foregroundStyle(textColor)` |
| Artist/album subtitle (both layouts) | `.foregroundStyle(.white.opacity(0.65))` | `.foregroundStyle(textColor.opacity(0.65))` |
| Backward/play/forward buttons (both layouts) | `.foregroundStyle(.white)` | `.foregroundStyle(textColor)` |

`nothingPlayingView` uses `.white.opacity(0.3)` against the default `.blue` background — update it to `textColor.opacity(0.3)` for consistency.

**File:** `DeskMat/Widgets/MediaControl/MediaControlWidget.swift`

---

## Testing

1. Play a track whose album art is predominantly white or cream — confirm text and controls render in a dark, tinted color rather than invisible white.
2. Play a track with a dark album — confirm text stays a light, tinted white.
3. Stop playback — confirm the widget resets to its default white-on-blue state without visual artifacts.
4. Toggle between art and no-art layouts (via the `mediaControlShowAlbumArt` setting) and verify both layouts update correctly.
