# TestWidget

## What it is

`TestWidget` is a developer-facing dock widget that exercises `PagedContainerView` end-to-end. It exists to verify that paged navigation works correctly and serves as a live reference for how to embed `PagedContainerView` inside a `DockWidget`. It is not intended for end users.

## Layout

```
┌────────────────────────────────────────────────────┐
│  [<]   Page N          (accent colour fill)   [>]  │
│                   • ○ ○                             │
└────────────────────────────────────────────────────┘
         label: Test Widget
```

- 2-cell `DockWidget` (128 × 64 pt)
- Contains a `PagedContainerView` with 3 pages
- Each page fills the content area with an accent colour and a centred page label

## Pages

| Index | Label  | Accent colour |
|-------|--------|---------------|
| 0     | Page 1 | Blue          |
| 1     | Page 2 | Purple        |
| 2     | Page 3 | Orange        |

Each page renders its label in white, small caps, centered.

## Visibility

Controlled by `@AppStorage("showTestWidget")`. Toggle appears in the Widgets section of Settings. No Pro gate — this is a dev widget.

## Wiring

- `ContentView` reads `@AppStorage("showTestWidget")` and renders `TestWidget()` in the widget HStack when true
- `showTestWidget` is included in `anyWidgetVisible` so the divider appears correctly

## Location

`DeskMat/Widgets/Test/TestWidget.swift`

## Dependencies

- `DockWidget` — outer container
- `PagedContainerView` — paged navigation
- No services, no network, no state beyond what `PagedContainerView` manages internally
