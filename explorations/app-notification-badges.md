# Exploration: App Notification Badge Counts

## What We Want

Show a count bubble on app icons in the dock — the red number that appears on app icons when they have unread notifications. Support visual settings to control its appearance (position, color, style, size).

---

## The Core Problem

macOS doesn't provide a public API for reading another app's badge count. The badge is owned by each app and rendered by the system Dock process. To read it from DeskMat, we have to go through the **Accessibility API**, which inspects the Dock's own accessibility tree at runtime.

---

## How the Dock Exposes Badge Counts

The Dock (`com.apple.dock`) is an `NSApplication` and its icon shelf is a full AX hierarchy. Each app icon in the Dock is an `AXUIElement` with `AXSubrole = "AXApplicationDockItem"`. That element carries an `AXStatusLabel` attribute whose value is the badge string as the system renders it:

| Dock badge state | `AXStatusLabel` value |
|---|---|
| No badge | `""` (empty string) |
| Numeric count | `"3"`, `"12"`, `"99+"` |
| Non-numeric alert | `"!"` |

The dock item also has `AXTitle` (the app name) but **not** `AXBundleIdentifier` as a direct attribute. Bundle IDs must be resolved separately by matching the PID of running apps against what the Dock shows — or by matching on `AXTitle` against known shortcut display names.

### Traversal path

```
AXUIElementCreateApplication(dockPID)
  └── AXChildren
        ├── AXList (persistent apps / running apps strip)
        │     └── AXDockItem  ← AXStatusLabel lives here
        └── AXList (trash, minimized windows)
```

The Dock typically has 2–3 child lists. The main app shelf is the first list whose children have `AXSubrole = "AXApplicationDockItem"`.

---

## Required Infrastructure

### 1. Accessibility permission

This is the only hard requirement. The user must grant DeskMat access in **System Settings → Privacy & Security → Accessibility**.

- Check at runtime: `AXIsProcessTrusted()`
- Prompt for permission: `AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: true] as CFDictionary)`
- If denied, badges silently don't show — no crash, no data leak

**App Store impact:** Accessibility API is allowed in sandboxed App Store apps, but requires a meaningful usage description string. Apple scrutinises this during review and will reject if the justification is weak. Outside the App Store (direct distribution), there are no restrictions.

The entitlement `com.apple.security.temporary-exception.accessibility` is sometimes needed for sandboxed builds targeting older macOS. Worth testing.

### 2. `BadgeService` — a new `@Observable` service

Same pattern as `WindowStateService`. One shared instance injected via `.environment()`. Polls at a fixed interval and caches results in a dictionary keyed by bundle ID.

```swift
@Observable
final class BadgeService {
    private(set) var badges: [String: String] = [:]  // bundleID → label string

    private var pollTimer: Timer?
    private let pollInterval: TimeInterval = 8.0

    func start() {
        guard pollTimer == nil else { return }
        poll()
        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval,
                                         repeats: true) { [weak self] _ in self?.poll() }
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    func badge(for bundleID: String) -> String? {
        let v = badges[bundleID]
        return (v?.isEmpty == false) ? v : nil
    }

    private func poll() {
        guard AXIsProcessTrusted() else { return }
        guard let dock = NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.apple.dock").first else { return }

        let dockElement = AXUIElementCreateApplication(dock.processIdentifier)
        var result: [String: String] = [:]

        // Walk lists of dock items
        var children: CFTypeRef?
        AXUIElementCopyAttributeValue(dockElement, kAXChildrenAttribute as CFString, &children)
        guard let lists = children as? [AXUIElement] else { return }

        for list in lists {
            var items: CFTypeRef?
            AXUIElementCopyAttributeValue(list, kAXChildrenAttribute as CFString, &items)
            guard let dockItems = items as? [AXUIElement] else { continue }

            for item in dockItems {
                var subrole: CFTypeRef?
                AXUIElementCopyAttributeValue(item, kAXSubroleAttribute as CFString, &subrole)
                guard (subrole as? String) == "AXApplicationDockItem" else { continue }

                var badge: CFTypeRef?
                AXUIElementCopyAttributeValue(item, "AXStatusLabel" as CFString, &badge)
                guard let badgeStr = badge as? String, !badgeStr.isEmpty else { continue }

                // Resolve which app this icon belongs to by matching AXTitle to running apps
                var title: CFTypeRef?
                AXUIElementCopyAttributeValue(item, kAXTitleAttribute as CFString, &title)
                if let name = title as? String,
                   let app = NSRunningApplication.runningApplications(withBundleIdentifier: "")
                       .first(where: { $0.localizedName == name }),
                   let bid = app.bundleIdentifier {
                    result[bid] = badgeStr
                }
            }
        }

        badges = result
    }
}
```

**Note on bundle ID resolution:** Matching by `AXTitle` against `NSRunningApplication.localizedName` works for running apps. For apps that are pinned but not running, the Dock item won't have a badge anyway, so this is fine.

A more robust approach: query all running apps once, build a `localizedName → bundleID` lookup table, and use that for the match — avoids per-item O(n) runningApplications calls.

### 3. Wiring into `AppShortcutButton`

Add `@Environment(BadgeService.self) private var badgeService` alongside the existing `windowState` environment. Then in the `ZStack` that holds the icon, add a `BadgeBubble` overlay:

```swift
// In AppShortcutButton, inside the outer ZStack (same level as the window indicator)
if let label = badgeService.badge(for: shortcut.bundleIdentifier) {
    BadgeBubble(label: label, style: badgeStyle, position: badgePosition)
        .frame(width: 64, height: 64, alignment: .topTrailing)
}
```

`BadgeBubble` is a small standalone view (see Visual Options below).

### 4. Permission prompt flow

Show a one-time prompt when the user enables the badge feature in settings:

```swift
if !AXIsProcessTrusted() {
    // Show a sheet explaining why, with "Open System Settings" and "Not Now"
    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
}
```

---

## Visual Options

### `BadgeBubble` view

```swift
struct BadgeBubble: View {
    let label: String         // "3", "99+", "!"
    var style: BadgeStyle     // from AppStorage
    var position: BadgePosition
}
```

### Settings knobs

| Setting | Key | Options |
|---|---|---|
| Show badges | `showBadges` | Bool toggle |
| Badge position | `badgePosition` | `.topTrailing` (default), `.topLeading`, `.bottomTrailing` |
| Badge color | `badgeColorHex` | Red (default), custom picker |
| Badge style | `badgeStyle` | `.filled`, `.outlined`, `.dot` |
| Badge size | `badgeSize` | `.small`, `.medium`, `.large` |
| Only show numeric | `badgeNumericOnly` | Bool — hide `"!"` style alerts |

**`.dot` style:** When the count is unknown or irrelevant, show just a small circle without a number. Useful for apps that post `"!"` rather than a count.

**`.outlined` style:** Transparent fill with a colored stroke — lower visual weight, good for users who find the red bubble distracting.

### Size constants

| Size | Circle diameter | Font size |
|---|---|---|
| small | 14 pt | 8 pt |
| medium | 18 pt | 10 pt |
| large | 22 pt | 12 pt |

Wide labels (`"99+"`) use a pill/capsule shape instead of a circle — same as iOS/macOS native badges.

---

## Performance Notes

- **Poll interval:** 8 seconds is a reasonable default. Badge counts rarely change faster than this in practice.
- **On-demand refresh:** Could also poll when the user's frontmost app changes (via `NSWorkspace.didActivateApplicationNotification`) since that's when new notifications typically arrive.
- **AX queries are synchronous and blocking** — run `poll()` on a background `DispatchQueue` and marshal results back to `@MainActor`.
- **Only poll when DeskMat is visible.** Wire `start()`/`stop()` to `onAppear`/`onDisappear` same as `SystemMonitorService`.

---

## Limitations and Risks

| Risk | Severity | Notes |
|---|---|---|
| Apple changes Dock AX tree structure | Medium | Has been stable since macOS 10.15 but is not a public API contract |
| `AXStatusLabel` attribute name changes | Low | Would silently return no badges; not a crash |
| Apps that don't use standard badges | N/A | Can only show what the Dock itself shows |
| User denies Accessibility | Low | Feature gracefully disabled; no fallback needed |
| App Store review rejection | Medium | Need a clear, honest usage description; direct distribution has no risk |
| Performance on large docks | Low | Linear in number of dock items; typically < 30 items |

---

## Files to Create / Modify

| File | Change |
|---|---|
| `BadgeService.swift` | New — `@Observable` service that polls the Dock AX tree |
| `BadgeBubble.swift` | New — small view for the count bubble itself |
| `AppShortcutButton.swift` | Add `@Environment(BadgeService.self)`, overlay in ZStack |
| `AppEnums.swift` | Add `BadgeStyle`, `BadgePosition`, `BadgeSize` enums |
| `SettingsView.swift` | Add badge section under widget/icon settings |
| `DeskMatApp.swift` | Inject `BadgeService` into environment |

---

## Open Questions

1. **Poll on notification vs timer?** Subscribing to `NSWorkspace.didActivateApplicationNotification` alongside the timer would make badge updates feel more responsive when switching apps, at low CPU cost.

2. **Per-app badge toggle?** A global on/off is enough to start. Per-app suppression (e.g. "don't show Slack's badge") would require storing a set of excluded bundle IDs in `AppStorage`.

3. **Unread count vs alert dot?** Some apps (Xcode, Terminal) show `"!"` rather than a number. Should the `"!"` be rendered as a dot, a `!` glyph, or suppressed? The `badgeNumericOnly` toggle covers this.

4. **First-run permission UX:** Should the accessibility prompt appear the first time the user opens settings, or only when they toggle the badge feature on? The latter is less intrusive.
