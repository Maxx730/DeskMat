# PagedContainerView

## What it is

`PagedContainerView` is a reusable SwiftUI container that displays one page of content at a time. Users navigate between pages with left and right chevron buttons. Navigation loops — pressing right on the last page returns to the first, and pressing left on the first page jumps to the last. Pages can also rotate automatically on a timer.

It is generic: callers provide the number of pages and a closure that maps a page index to a view. The container manages all navigation state internally.

## Layout

```
┌─────────────────────────────────────────┐
│  [<]   [ current page content ]   [>]  │
│              • • ○ •                    │
└─────────────────────────────────────────┘
```

- Left chevron (`chevron.left`) — navigates to the previous page (hidden when `showChevrons: false`)
- Content area — fills the space between the chevrons (or the full width when chevrons are hidden)
- Right chevron (`chevron.right`) — navigates to the next page (hidden when `showChevrons: false`)
- Page dots (optional) — centered below the content, one dot per page; filled dot indicates current page

## Navigation

| Action              | Result                                      |
|---------------------|---------------------------------------------|
| Tap right chevron   | Advance to next page; wrap to 0 from last   |
| Tap left chevron    | Go to previous page; wrap to last from 0    |
| Auto-rotate tick    | Advance to next page (forward direction)    |

Navigation direction is tracked so the slide transition animates the correct way.

## Transitions

Pages slide in and out horizontally using `.asymmetric` transitions:

- **Forward** (right chevron or auto-rotate): outgoing page exits to the left, incoming page enters from the right
- **Backward** (left chevron): outgoing page exits to the right, incoming page enters from the left

Animation: `.easeInOut(duration: 0.25)`.

## Page Dots

When `showDots: true` (default), a row of small circles appears below the content:

- Filled circle — current page
- Faded circle — other pages
- Size: 4pt diameter, 6pt spacing
- Hidden when `pageCount == 1`

## Auto-Rotate

When `autoRotate: true`, the view automatically advances to the next page after `autoRotateInterval` seconds. Any manual navigation (chevron tap) resets the timer. Auto-rotate always advances in the forward direction and loops back to the first page from the last.

Auto-rotate is implemented via a `.task` keyed on an internal `rotateEpoch` counter that increments on every navigation, cancelling and restarting the sleep timer.

## API

```swift
// Manual navigation only
PagedContainerView(pageCount: 3) { index in
    Text("Page \(index + 1)")
}

// Auto-rotate, no chevrons, no dots
PagedContainerView(pageCount: 3, showChevrons: false, showDots: false, autoRotate: true, autoRotateInterval: 5.0) { index in
    Text("Page \(index + 1)")
}
```

## Parameters

| Parameter            | Type            | Default | Description                                        |
|----------------------|-----------------|---------|----------------------------------------------------|
| `pageCount`          | `Int`           | —       | Total number of pages                              |
| `showChevrons`       | `Bool`          | `true`  | Show left/right chevron navigation buttons         |
| `showDots`           | `Bool`          | `true`  | Show page indicator dots below content             |
| `autoRotate`         | `Bool`          | `false` | Automatically advance pages on a timer             |
| `autoRotateInterval` | `Double`        | `3.0`   | Seconds between auto-rotate advances               |
| `content`            | `(Int) -> View` | —       | View builder; receives the page index              |

## Internal state

| Property      | Type               | Description                                              |
|---------------|--------------------|----------------------------------------------------------|
| `currentPage` | `@State Int`       | Index of the currently visible page                      |
| `direction`   | `@State Direction` | Last navigation direction for transition                 |
| `rotateEpoch` | `@State Int`       | Increments on every navigation to reset the auto-rotate timer |

`Direction` is an internal enum with cases `.forward` and `.backward`.

## Constraints

- `pageCount` must be ≥ 1. With exactly 1 page, chevrons are hidden, dots are not shown, and auto-rotate does nothing.
- The view does not scroll — it is not a replacement for `TabView` with page style. Each page is a discrete view, not a continuous scroll surface.
- Content views are responsible for their own sizing. `PagedContainerView` does not impose a fixed size on page content.
- When `showChevrons: false`, chevron tap targets are removed entirely; the full width is given to content.

## Location

`DeskMat/Utilities/PagedContainerView.swift`
