# Plan: Close All Windows Context Menu Item

## Goal

Add a "Close All Windows" option to the right-click context menu on app shortcut buttons. Tapping it closes every open window of that app without quitting it.

---

## Current State

The context menu in `AppShortcutButton.swift` (line 115) has two items:
```swift
.contextMenu {
    Button(Strings.Menu.edit) { ... }
    Button(Strings.Menu.remove, role: .destructive) { onRemove() }
}
```

`AppShortcutButton` already tracks `isFrontmost` by observing `NSWorkspace.didActivateApplicationNotification`. The `shortcut.bundleIdentifier` is available on the button.

---

## Implementation Approach

**AppleScript** via `NSAppleScript`:
```applescript
tell application id "com.apple.safari" to close every window
```

This is the right tool: it closes windows without quitting the app, works for all mainstream apps (Safari, Chrome, VS Code, Finder, Terminal, etc.), and is the standard way sandboxed apps interact with other apps on macOS.

**Sandbox requirement:** Add `com.apple.security.automation.apple-events` to the entitlements. The first time DeskMat tries to send an Apple Event to a given app, macOS shows a one-time permission prompt: "DeskMat wants to control [App]." The user approves once per app; after that it's remembered.

---

## Phases

---

### Phase 1 — "Close All Windows" menu item with running state

**Files:** `AppShortcutButton.swift`, `Strings.swift`

#### Running state tracking

`AppShortcutButton` already subscribes to `didActivateApplicationNotification` to track `isFrontmost`. Extend this to track whether the app is running at all, using launch and terminate notifications:

```swift
@State private var isRunning: Bool = false
```

Seed the initial value on appear:
```swift
.onAppear {
    isRunning = NSWorkspace.shared.runningApplications
        .contains { $0.bundleIdentifier == shortcut.bundleIdentifier }
}
```

Update via two additional `.onReceive` publishers:
```swift
.onReceive(NSWorkspace.shared.notificationCenter
    .publisher(for: NSWorkspace.didLaunchApplicationNotification)) { notification in
    if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
       app.bundleIdentifier == shortcut.bundleIdentifier {
        isRunning = true
    }
}
.onReceive(NSWorkspace.shared.notificationCenter
    .publisher(for: NSWorkspace.didTerminateApplicationNotification)) { notification in
    if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
       app.bundleIdentifier == shortcut.bundleIdentifier {
        isRunning = false
    }
}
```

#### Menu item

Add "Close All Windows" above the destructive "Remove" button, only visible when `isRunning`:

```swift
.contextMenu {
    Button(Strings.Menu.edit) {
        NotificationCenter.default.post(name: .editShortcut, object: shortcut)
    }
    if isRunning {
        Divider()
        Button(Strings.Menu.closeAllWindows) {
            closeAllWindows()
        }
    }
    Button(Strings.Menu.remove, role: .destructive) { onRemove() }
}
```

#### String

In `Strings.Menu`:
```swift
static let closeAllWindows = "Close All Windows"
```

---

### Phase 2 — Close action implementation

**Files:** `AppShortcutButton.swift`, `DeskMat.entitlements`, `Info.plist`

#### Entitlement

Add to `DeskMat.entitlements`:
```xml
<key>com.apple.security.automation.apple-events</key>
<true/>
```

#### Info.plist usage description

Add to `Info.plist` (shown in the system permission prompt):
```xml
<key>NSAppleEventsUsageDescription</key>
<string>DeskMat uses Apple Events to close windows of apps in your dock.</string>
```

#### The close function

Add as a private method on `AppShortcutButton`:

```swift
private func closeAllWindows() {
    guard let bundleID = shortcut.bundleIdentifier else { return }
    let source = "tell application id \"\(bundleID)\" to close every window"
    DispatchQueue.global(qos: .userInitiated).async {
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        // Silent failure — if the app isn't scriptable, nothing happens.
        // The user's intent was best-effort; no alert needed.
    }
}
```

Run on the main thread — `NSAppleScript` is not thread-safe and silently fails when called off the main thread. The script completes fast enough that blocking the main thread briefly is not noticeable.

---

### Phase 3 — Finder special case + edge cases

**File:** `AppShortcutButton.swift`

#### Finder

`close every window` works on Finder but also closes the desktop (which is a Finder window internally on some macOS versions). The safer script for Finder is:

```applescript
tell application "Finder" to close every Finder window
```

Detect Finder by bundle ID and use the appropriate script:

```swift
private func closeAllWindows() {
    guard let bundleID = shortcut.bundleIdentifier else { return }
    let source: String
    if bundleID == "com.apple.finder" {
        source = "tell application \"Finder\" to close every Finder window"
    } else {
        source = "tell application id \"\(bundleID)\" to close every window"
    }
    DispatchQueue.global(qos: .userInitiated).async {
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
    }
}
```

#### App has no open windows

The AppleScript succeeds silently — `close every window` with zero windows is a no-op. No handling needed.

#### App is not scriptable

`executeAndReturnError` returns an error dict. Fail silently — the user clicked "Close All Windows" on a non-scriptable app; nothing they can do about it and an alert would be more confusing than the silence. The menu item disappears as an option once the app quits anyway.

---

## Files Changed

| File | Change |
|---|---|
| `AppShortcutButton.swift` | Add `isRunning` state, launch/terminate observers, `closeAllWindows()`, menu item |
| `Strings.swift` | Add `Strings.Menu.closeAllWindows` |
| `DeskMat.entitlements` | Add `com.apple.security.automation.apple-events` |
| `Info.plist` | Add `NSAppleEventsUsageDescription` |

---

## Notes

- The permission prompt ("DeskMat wants to control Safari") appears once per app, the first time the user triggers "Close All Windows" for it. After that it's silent.
- The menu item is hidden (not just disabled) when the app isn't running — no point showing it for a closed app.
- No new windows, services, or notification names are needed.
