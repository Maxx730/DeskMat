# Test Widget — Paged Container

## Overview

A new `TestWidget` that renders inside a standard `DockWidget` and contains a `PagedContainerView` — a reusable sub-container that displays one page of content at a time, navigated by left and right chevron buttons that loop through pages infinitely.

The `PagedContainerView` is designed to be reusable by other widgets in the future.

---

## Phase 1 — Specs

Write specs before any code. No implementation in this phase.

**Deliverables:**
- `specs/PagedContainerView.md`
- `specs/TestWidget.md`

Both specs must be approved before moving to Phase 2.

---

## Phase 2 — Implement `PagedContainerView`

Create the reusable paged container as a generic SwiftUI view.

**File:** `DeskMat/Utilities/PagedContainerView.swift`

### Behaviour

- Accepts an array of page-count and a `@ViewBuilder` that maps an index to a page view
- Tracks `currentPage: Int` in `@State`
- Left chevron decrements: `(currentPage - 1 + pageCount) % pageCount`
- Right chevron increments: `(currentPage + 1) % pageCount`
- Animated slide transition: sliding left when going forward, right when going backward
- Transition direction tracked via a `NavigationDirection` enum (`.forward`, `.backward`)

### Layout

```
[ < ]  [ current page content ]  [ > ]
```

- Chevrons are `chevron.left` / `chevron.right` system images
- Chevron tap targets are generously sized (min 24×44 pt) for usability
- Content area fills the remaining width between the two chevrons
- Optional page indicator dots centered below the content

### API

```swift
PagedContainerView(pageCount: Int, showDots: Bool = true) { index in
    // return view for page at index
}
```

### Transition

Use `.asymmetric` transitions with `.move(edge:)` so the outgoing page exits opposite to the incoming page:
- Forward: old page exits left, new page enters from right
- Backward: old page exits right, new page enters from left

Wrap in `withAnimation(.easeInOut(duration: 0.25))`.

---

## Phase 3 — Implement `TestWidget`

Create the test widget that exercises `PagedContainerView` with three placeholder pages.

**File:** `DeskMat/Widgets/Test/TestWidget.swift`

### Behaviour

- Wraps content in `DockWidget(cells: 2)`
- Contains a `PagedContainerView` with 3 pages
- Each page is a simple placeholder showing its page number and a distinct accent colour
- No data fetching, no services — purely a UI test bed

### Placeholder pages

| Page | Label    | Accent colour |
|------|----------|---------------|
| 0    | Page 1   | Blue          |
| 1    | Page 2   | Purple        |
| 2    | Page 3   | Orange        |

### Wire into ContentView

1. Add `@AppStorage("showTestWidget") private var showTestWidget = false` to `ContentView`
2. Add `TestWidget()` to the widget HStack (no Pro gate — this is a dev widget)
3. Add `showTestWidget` to the `anyWidgetVisible` computed property

---

## Phase 4 — Settings Toggle

Add a toggle in `SettingsView` so the widget can be shown/hidden without editing code.

- Add `@AppStorage("showTestWidget") private var showTestWidget = false` to `SettingsView`
- Add a toggle row labelled "Test Widget" in the Widgets settings section
- No Pro badge needed (dev-only widget)

---

## Done

`PagedContainerView` is available for reuse by other widgets. `TestWidget` demonstrates it working end-to-end and can be toggled from Settings.
