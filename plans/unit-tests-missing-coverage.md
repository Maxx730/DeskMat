# Missing Unit Test Coverage

## Summary

The project has 45 test files with solid coverage across most of the codebase (Swift Testing framework, `@Test` / `#expect`). Three gaps were found after surveying all existing tests and matching them against testable pure logic.

---

## Gap 1 — `MediaControlWidget.contrastingTextColor`

**File:** `DeskMat/Widgets/MediaControl/MediaControlWidget.swift`
**Test file to create:** `DeskMatTests/MediaControlContrastTests.swift`

This is the method we just implemented. It is `private static`, so `@testable import` alone won't expose it. Before tests can be written, the access level must change to `internal static` (drop `private`).

### Required source change

```swift
// Before
private static func contrastingTextColor(for background: Color, tintStrength: CGFloat = 0.15) -> Color

// After
static func contrastingTextColor(for background: Color, tintStrength: CGFloat = 0.15) -> Color
```

### Tests to write

**Suite: `ContrastingTextColorLuminanceTests`**

| Test name | Input color | Expected outcome |
|---|---|---|
| `darkBackgroundYieldsLightText` | Pure black (`#000000`) | R, G, B channels all > 0.8 |
| `lightBackgroundYieldsDarkText` | Pure white (`#FFFFFF`) | R, G, B channels all < 0.2 |
| `midGreyAboveThresholdYieldsDarkText` | `#808080` (luminance ≈ 0.216 > 0.179) | R, G, B channels all < 0.2 |
| `midGreyBelowThresholdYieldsLightText` | `#606060` (luminance ≈ 0.118 < 0.179) | R, G, B channels all > 0.8 |
| `defaultTintStrengthIs0_15` | Call with only `background:` param | Verify result differs from pure base color by ≤ 15% per channel |
| `zeroTintStrengthReturnsPureBase` | Black bg, `tintStrength: 0` | R = G = B = 1.0 (pure white) |
| `fullTintStrengthReturnsBgColor` | Any color, `tintStrength: 1.0` | Returned color channels match input color channels |
| `invalidNSColorFallbackReturnsWhite` | A `Color` that cannot convert to sRGB (e.g. `Color(hue:…)` edge case) | Result is `.white` |

**Suite: `ContrastingTextColorTintTests`**

| Test name | Description |
|---|---|
| `redBackgroundTintsLightText` | Dark red background → result should have higher R channel than G/B (red tint on light base) |
| `blueBackgroundTintsDarkText` | Light blue background → result should have higher B channel (blue tint on dark base) |
| `tintStrengthScalesLinearly` | At 0.15 and 0.30, the delta from pure base should be proportional |

---

## Gap 2 — `TasksStore`

**File:** `DeskMat/Widgets/Tasks/TasksStore.swift`
**Test file to create:** `DeskMatTests/TasksStoreTests.swift`

`TasksStore` has no tests at all. Its `save()` and `load()` methods write to `UserDefaults.standard` under the key `"tasksWidgetData"`. Tests must save and restore the original value so they don't contaminate the real user data.

No source changes needed — `TasksStore` and `TaskItem` are `internal` and reachable via `@testable import`.

### Tests to write

**Suite: `TaskItemTests`**  
(pure struct, no UserDefaults)

| Test name | Description |
|---|---|
| `defaultIsDoneIsFalse` | Newly created `TaskItem` has `isDone == false` |
| `defaultDescriptionIsEmpty` | Newly created `TaskItem` has `description == ""` |
| `eachItemHasUniqueID` | Two items created with the same title have different `id` values |
| `codableRoundTrip` | Encode then decode a `TaskItem`, verify all fields match |
| `codableRoundTripWithDescription` | Same with a non-empty `description` |
| `codableRoundTripIsDoneTrue` | Encode a completed item, decode, verify `isDone == true` |

**Suite: `TasksStoreTests`**  
(must save/restore `UserDefaults` around each test — use `@Suite(.serialized)`)

| Test name | Description |
|---|---|
| `startsEmptyWithNoPersistedData` | After clearing the defaults key, `init()` produces `tasks == []` |
| `addAppendsTask` | After `add(title:)`, `tasks.count == 1` and `tasks[0].title` matches |
| `addWithDescriptionStoresDescription` | `add(title:description:)` stores both fields |
| `addMultipleTasks` | Three `add` calls → `tasks.count == 3` in insertion order |
| `toggleFlipsDoneState` | After `add` then `toggle`, `tasks[0].isDone == true` |
| `toggleIdempotentOnDoubleCall` | `toggle` twice returns item to `isDone == false` |
| `toggleIgnoresUnknownID` | Calling `toggle` with a `TaskItem` not in the store does not crash or mutate |
| `deleteRemovesAtIndex` | `delete(at: [0])` on a two-item store leaves one item |
| `deleteAllLeavesEmpty` | `delete(at: [0, 1])` on a two-item store leaves `tasks == []` |
| `persistenceRoundTrip` | Add two tasks, create a second `TasksStore` instance, verify both tasks load back |
| `togglePersists` | Toggle an item, reload store, verify `isDone` is still `true` |
| `deletePersists` | Delete an item, reload store, verify it's gone |

---

## Gap 3 — `LEDBoardWidget.buildPixelGrid` aspect-ratio logic

**File:** `DeskMat/Widgets/LEDBoard/LEDBoardWidget.swift`
**Test file:** `DeskMatTests/LEDBoardTests.swift` (extend existing file — key constants are already there)

`buildPixelGrid` is `private`, so it must be changed to `internal` before tests can access it. Alternatively, the centering-offset and aspect-ratio math can be extracted into a small `internal` pure function.

### Required source change

```swift
// Before
private func buildPixelGrid(...)

// After
func buildPixelGrid(...)
```

Or extract the math into a standalone `internal` helper:

```swift
/// Returns (scaledWidth, scaledHeight, xOffset, yOffset) for fitting
/// a source of `srcW × srcH` into a grid of `cols × rows` cells.
static func gridFitMetrics(srcW: Int, srcH: Int, cols: Int, rows: Int)
    -> (scaledW: Int, scaledH: Int, xOff: Int, yOff: Int)
```

### Tests to write

**Suite: `LEDBoardGridFitTests`** (add to existing `LEDBoardTests.swift`)

| Test name | Description |
|---|---|
| `squareImageFillsSquareGrid` | 10×10 source into 10×10 grid → `scaledW == 10, scaledH == 10, xOff == 0, yOff == 0` |
| `wideImageCentersVertically` | 20×10 source into 10×10 grid → scaled to 10×5, `yOff == 2` (centered) |
| `tallImageCentersHorizontally` | 10×20 source into 10×10 grid → scaled to 5×10, `xOff == 2` (centered) |
| `gridLargerThanSourceScalesUp` | 2×2 source into 10×10 grid → `scaledW == 10, scaledH == 10` |
| `minimumGridDimensionIsOne` | 1×1 source into 1×1 grid → `scaledW == 1, scaledH == 1, xOff == 0, yOff == 0` |
| `aspectRatioPreserved` | Verify `scaledW / scaledH` matches `srcW / srcH` within rounding |

---

## Files to Create / Modify

| Action | File |
|---|---|
| Create | `DeskMatTests/MediaControlContrastTests.swift` |
| Create | `DeskMatTests/TasksStoreTests.swift` |
| Extend | `DeskMatTests/LEDBoardTests.swift` |
| Modify (visibility) | `DeskMat/Widgets/MediaControl/MediaControlWidget.swift` — `private static` → `static` on `contrastingTextColor` |
| Modify (visibility) | `DeskMat/Widgets/LEDBoard/LEDBoardWidget.swift` — `private` → `internal` on `buildPixelGrid`, or extract helper |
