# Plan: Update Checking

## Goal

On every app launch, silently check whether a newer version of DeskMat is available using the existing `auth.cepholotech.com` backend. Also expose a "Check for Updates..." item in the status bar menu so the user can trigger a check manually. When an update is found, notify the user and give them a one-click path to download it.

---

## Endpoint

```
GET https://auth.cepholotech.com/versions/check
    ?product_id=784415ba-f43c-4a21-91c7-ec9ad1968406
    &platform=mac
    &current_version=<CFBundleShortVersionString>
```

No auth required. Rate limit: 20 req/min per IP (not a concern for a per-user client).

**Up to date response:**
```json
{ "up_to_date": true, "latest_version": "1.2.0" }
```

**Update available response:**
```json
{
  "up_to_date": false,
  "latest_version": "1.3.0",
  "download_url": "https://cdn.example.com/deskmat-1.3.0.dmg",
  "release_notes": "Bug fixes and performance improvements.",
  "file_size": 10485760,
  "file_hash": "abc123..."
}
```

---

## Architecture

One new file (`UpdateService.swift`) plus changes to `AppDelegate` and `Strings.swift`. No new UI files — the manual check result is an `NSAlert`, and the launch check uses the existing `sendNotification` infrastructure.

---

## Phases

---

### Phase 1 — `UpdateService`

**Scope:** `UpdateService.swift` (new file)

An `@Observable` class that owns all network and state logic. Pattern matches `WindowStateService` and `SystemMonitorService`.

**State:**
```swift
@Observable
final class UpdateService {
    private(set) var isChecking:       Bool    = false
    private(set) var isUpdateAvailable: Bool   = false
    private(set) var latestVersion:    String  = ""
    private(set) var downloadURL:      URL?    = nil
    private(set) var releaseNotes:     String? = nil
}
```

**Response model:**
```swift
private struct VersionCheckResponse: Codable {
    let upToDate:      Bool
    let latestVersion: String
    let downloadURL:   URL?
    let releaseNotes:  String?

    enum CodingKeys: String, CodingKey {
        case upToDate      = "up_to_date"
        case latestVersion = "latest_version"
        case downloadURL   = "download_url"
        case releaseNotes  = "release_notes"
    }
}
```

**`check()` method:**
```swift
func check() async {
    guard !isChecking else { return }

    let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    var components = URLComponents(string: "https://auth.cepholotech.com/versions/check")!
    components.queryItems = [
        URLQueryItem(name: "product_id",      value: "784415ba-f43c-4a21-91c7-ec9ad1968406"),
        URLQueryItem(name: "platform",        value: "mac"),
        URLQueryItem(name: "current_version", value: currentVersion),
    ]

    await MainActor.run { isChecking = true }
    defer { Task { @MainActor in isChecking = false } }

    do {
        let (data, response) = try await URLSession.shared.data(from: components.url!)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return }
        let decoded = try JSONDecoder().decode(VersionCheckResponse.self, from: data)

        UserDefaults.standard.set(Date(), forKey: "lastUpdateCheckDate")

        await MainActor.run {
            latestVersion     = decoded.latestVersion
            isUpdateAvailable = !decoded.upToDate
            downloadURL       = decoded.downloadURL
            releaseNotes      = decoded.releaseNotes
        }
    } catch {
        // Silent failure — update check is best-effort
    }
}
```

**Throttle:** Before calling `check()` on launch, read `UserDefaults.standard.object(forKey: "lastUpdateCheckDate") as? Date`. If it was less than 1 hour ago, skip the network call and use cached `isUpdateAvailable` state instead.

---

### Phase 2 — Auto-check on launch + notification

**Scope:** `DeskMatApp.swift` (`AppDelegate`)

1. Add `let updateService = UpdateService()` alongside the other services at the top of `AppDelegate`.

2. At the end of `applicationDidFinishLaunching`, fire the check asynchronously — it must not block the UI:
   ```swift
   Task {
       await updateService.check()
       if updateService.isUpdateAvailable {
           sendNotification(
               title: Strings.Updates.notificationTitle,
               body:  Strings.Updates.notificationBody(updateService.latestVersion)
           )
       }
   }
   ```

   `sendNotification` already exists in `AppDelegate` — no new infrastructure needed.

3. The notification body example: `"DeskMat 1.3.0 is available. Open DeskMat settings to download."` — directs the user to the manual menu item rather than deep-linking, which avoids complexity.

---

### Phase 3 — "Check for Updates..." menu item

**Scope:** `DeskMatApp.swift` (`AppDelegate.setupStatusItem()`)

**Menu item placement:** After the separator that currently precedes the Settings item — keeping update-related actions near the bottom of the menu, just above Settings and Quit.

```swift
menu.addItem(NSMenuItem(title: Strings.Menu.checkForUpdates,
                        action: #selector(checkForUpdates),
                        keyEquivalent: ""))
menu.addItem(NSMenuItem.separator())
menu.addItem(NSMenuItem(title: Strings.Menu.settings, ...))
```

**`checkForUpdates` selector:**
```swift
@objc private func checkForUpdates() {
    Task {
        await updateService.check()
        await MainActor.run { showUpdateResult() }
    }
}
```

**`showUpdateResult()`** builds and runs an `NSAlert`:

- **Update available:**
  - Title: `"DeskMat \(updateService.latestVersion) Available"`
  - Message: release notes string (or a fallback if nil)
  - Buttons: `"Download"` (primary), `"Later"`
  - Clicking "Download": `NSWorkspace.shared.open(updateService.downloadURL!)`

- **Up to date:**
  - Title: `"DeskMat is up to date"`
  - Message: `"Version \(currentVersion) is the latest release."`
  - Button: `"OK"`

- **While checking (isChecking = true):** Disable the menu item by setting its `isEnabled = false` and title to `"Checking..."`. Re-enable when check completes. Store a reference to the item: `var checkForUpdatesMenuItem: NSMenuItem?` on `AppDelegate` alongside the existing `exportDockMenuItem`.

---

## Strings to Add

In `Strings.swift`, add a new `Updates` namespace:

```swift
enum Updates {
    static let notificationTitle = "Update Available"
    static func notificationBody(_ version: String) -> String {
        "DeskMat \(version) is available. Check for Updates in the menu bar."
    }
}
```

In `Strings.Menu`, add:
```swift
static let checkForUpdates = "Check for Updates..."
```

---

## Files Changed

| File | Change |
|---|---|
| `UpdateService.swift` | New — service with `check()`, response model, state |
| `DeskMatApp.swift` | Add `updateService` instance, launch check, selector, menu item |
| `Strings.swift` | Add `Strings.Updates` namespace and `Strings.Menu.checkForUpdates` |

---

## What Stays the Same

- No new settings UI — the check is always-on and silent on launch
- `sendNotification` in `AppDelegate` is used as-is
- The sandboxed app never attempts to replace its own bundle — download always opens in the browser/Finder
- No entitlement changes required (`network.client` already present)

---

## Open Questions

1. **Throttle interval:** 1 hour is conservative. Could move to 24 hours since DeskMat doesn't release that frequently. Easy to adjust — it's a single constant.

2. **Beta channel:** The endpoint supports a `channel=beta` parameter. Could expose this as a toggle in `SettingsView` (Pro only) in a future pass. For now, always use stable.

3. **Notification on every launch vs. once per version:** The current plan fires a notification every launch that an update is available. A guard against `UserDefaults.standard.string(forKey: "lastNotifiedVersion")` would suppress repeat notifications for the same version across relaunches. Worth adding to Phase 2 before shipping.
