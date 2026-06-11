# DockWidget

## What it is

`DockWidget` is the standard container view that all widgets in the dock are built inside. It provides a consistent size, background appearance, loading state, hover effect, and optional refresh button. Widgets supply their own content via a `@ViewBuilder` closure — `DockWidget` handles everything around it.

## Size

Widgets are measured in **cells**. One cell is 64×64 points.

| cells | width  | height (default) |
|-------|--------|------------------|
| 1     | 64 pt  | 64 pt            |
| 2     | 128 pt | 64 pt            |
| 3     | 192 pt | 64 pt            |

Height can be overridden via the `height` parameter. Width is always `cells × 64`.

## Background

Two modes depending on whether a `backgroundColor` is provided:

**Default (no backgroundColor)**
- Dark frosted glass look: black at 30% opacity fill, black at 50% opacity 1pt stroke
- Inner highlight: white at 10% opacity fill and stroke inset by 1pt, giving a subtle raised edge
- On hover: fill lightens from 30% → 15% opacity with a 0.15s ease transition

**Custom backgroundColor**
- Fills the rounded rect with the given color directly
- No hover lightening, no inner highlight stroke
- Used by themed widgets (e.g. Eve faction themes) that manage their own background appearance

Both modes use a corner radius of 10pt.

## Loading state

When `isLoading: true`, the widget hides its content and shows a small white `ProgressView` (spinner) scaled to 70% in the center. When `isLoading` returns to `false`, the content reappears.

## Hover effect

When `hoverEffect: true` (default) and the cursor enters the widget, `isHovering` flips to `true` and the background lightens. This is disabled for widgets where hover is managed externally or not desired.

## Refresh button

When `onRefresh` is provided, a small clockwise arrow icon appears in the top-trailing corner. Tapping it calls `onRefresh()` as an async Task. Opacity is 60% to keep it subtle. Not shown when `onRefresh` is nil.

## Parameters

| Parameter       | Type                     | Default  | Description                              |
|-----------------|--------------------------|----------|------------------------------------------|
| `cells`         | `Int`                    | `1`      | Width in cell units (1 cell = 64pt)      |
| `height`        | `CGFloat`                | `64`     | Height in points                         |
| `isLoading`     | `Bool`                   | `false`  | Show spinner instead of content          |
| `hoverEffect`   | `Bool`                   | `true`   | Lighten background on hover              |
| `backgroundColor` | `Color?`               | `nil`    | Custom fill; bypasses default glass look |
| `onRefresh`     | `(() async -> Void)?`    | `nil`    | Shows refresh button when provided       |
| `content`       | `@ViewBuilder`           | required | The widget's content view                |

## Usage example

```swift
DockWidget(cells: 2, isLoading: isLoading, onRefresh: { await service.refresh() }) {
    Text("Hello")
}
```

## Static helpers

```swift
DockWidget<EmptyView>.cellSize          // 64.0
DockWidget<EmptyView>.width(for: 2)    // 128.0
```

Used by widgets to size their label frames to match the widget width without hardcoding a number.

## Where it is used

Every widget in the dock wraps its content in a `DockWidget`:
- `ClockWidget` — 2 cells
- `EveWidget` — 2 cells
- `ImageWidget` — 1 cell
- `LEDBoardWidget` — variable
- `SystemWidget` — 2 cells
- `WeatherWidget` — 2 cells
