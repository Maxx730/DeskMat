# Exploration: Web Frame Widget (2x)

## Overview

A widget that loads a user-specified URL and renders it live inside a 2-cell widget slot. The core technology on macOS is `WKWebView` from WebKit — the same engine that powers Safari. It supports JavaScript, CSS, cookies, sessions, and network requests, making it far more capable than a simple screenshot approach.

---

## What's Actually Possible

### WKWebView in a SwiftUI Widget

SwiftUI does not have a native web view component. The bridge is `NSViewRepresentable`:

```swift
import WebKit
import SwiftUI

struct WebView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if webView.url != url {
            webView.load(URLRequest(url: url))
        }
    }
}
```

Dropped into the widget body like any other SwiftUI view:

```swift
struct WebFrameWidget: View {
    static let cellCount = 2

    @AppStorage("webFrameURL") private var rawURL = "https://example.com"

    private var url: URL? { URL(string: rawURL) }

    var body: some View {
        Group {
            if let url {
                WebView(url: url)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Text("Invalid URL")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

The widget slot follows the existing `cellCount = 2` convention used by Weather and Eve.

---

## Can the Framed Site Make Network Requests?

**Yes, fully.** `WKWebView` runs a real browser engine. The loaded page:

- Executes JavaScript (fetch, XMLHttpRequest, WebSockets)
- Sends/receives cookies and credentials with the origin's server
- Loads sub-resources (images, scripts, fonts) from third-party domains
- Follows redirects
- Maintains a persistent session (WKWebsiteDataStore)

The requests originate from the macOS process, so they use the machine's IP and the app's sandbox network entitlement (`com.apple.security.network.client`), which DeskMat almost certainly already has for weather/Eve data.

One constraint: **cross-origin requests from page JS** are still subject to the target server's CORS policy. A page trying to `fetch('https://other-api.com')` will be blocked if that server doesn't send `Access-Control-Allow-Origin`. The native process itself is not affected; only in-page JavaScript is.

---

## Limitations

### Sandboxing & File System
- App Sandbox prevents the web view from accessing arbitrary local files unless the user explicitly grants a security-scoped bookmark. `file://` URLs to paths outside the app container will fail silently or show a blank page.

### Interaction Model — the Hardest Problem
DeskMat's widget area is a panel window positioned over the desktop. `WKWebView` receives mouse events normally in a standard window, but the widget panel's `NSWindow` style and level matter:

- If the panel has `ignoresMouseEvents = true` (common for always-on-top overlays), clicks pass through and never reach the web view.
- If mouse events are enabled, the web view becomes interactive: scrolling, clicking links, filling forms all work. But this fights with the dock drag-and-drop and widget rearranging gestures DeskMat uses.
- The practical middle ground is a **toggle**: default pass-through (overlay mode), press a hotkey or click a "lock" button to hand focus to the web view.

### JavaScript Popups & New Windows
`WKWebView` suppresses `window.open()` calls and `<a target="_blank">` unless you implement `WKUIDelegate`. Without it, those links are silently ignored, which can break some dashboards.

### Rendering Quirks
- Pages designed for mobile or narrow viewports may render poorly at widget dimensions (roughly 380×220 px for a 2x slot on a typical display).
- A fixed viewport meta injection can help:
  ```swift
  let script = WKUserScript(
      source: "document.querySelector('meta[name=viewport]')?.setAttribute('content','width=1200,initial-scale=1');",
      injectionTime: .atDocumentEnd,
      forMainFrameOnly: true
  )
  config.userContentController.addUserScript(script)
  ```
- `WKWebView` does not support Flash (dead) or certain browser extensions that depend on low-level APIs.

### Performance
A live web view is meaningfully heavier than DeskMat's other widgets — a JS-heavy dashboard (stock ticker, live map) can pin a CPU core. Worth offering a **refresh-on-interval** mode (reload every N seconds) rather than always-live as a mitigation.

### Authentication / Login Walls
Pages behind a login form work — the user can interact with the login form if mouse events are enabled. Session cookies persist in `WKWebsiteDataStore.default()`. The first time requires interaction; subsequent app launches reuse the stored session automatically.

Pages using SSO (OAuth redirect flows) work too, as long as the final post-auth redirect lands back inside the same web view and not in a system browser tab.

---

## Security Considerations

### What the Site Can Do
- Execute arbitrary JavaScript in the web view's process context (normal for any browser tab — not elevated).
- Store cookies and local storage in the app's WebKit data store. This is isolated per-app, separate from Safari's store.
- Make network requests to any host permitted by the app's sandbox entitlements — effectively anything with `com.apple.security.network.client`.
- **Cannot** reach the Swift/AppKit layer or access DeskMat's `@AppStorage` values unless you deliberately expose a `WKScriptMessageHandler`.

### What It Cannot Do Without Explicit Wiring
- Call native APIs or read local files outside its sandboxed data store.
- Communicate with other apps or inject into other processes.
- Access the clipboard unless the user triggers a paste (App Sandbox clipboard rule).
- Interact with the macOS Keychain (requires explicit entitlement + API calls from native code).

### Risks to Watch

| Risk | Severity | Mitigation |
|---|---|---|
| Malicious URL set by user executes JS that exfiltrates cookies from the same WKWebsiteDataStore | Low-Medium | Use a non-default, isolated `WKWebsiteDataStore` per web view instance so the site can only access its own cookies |
| JS injection via a compromised page altering `WKScriptMessageHandler` bridge | Medium if bridge exposed | Do not expose a script message handler unless needed; if you do, validate all messages |
| User accidentally stores credentials for a sensitive service in the widget's session | Low | Document that the widget's session is separate from Safari; offer a "Clear Session" button in settings |
| Resource exhaustion from a heavy live page | Low | Cap refresh interval; consider pausing the web view when DeskMat is hidden |
| Mixed-content (HTTPS page loading HTTP sub-resources) | Low | WKWebView follows Apple Platform Security; mixed active content is blocked by default |

### Recommended Hardening

```swift
// Use a per-widget isolated data store — no shared cookies with anything else
let store = WKWebsiteDataStore.nonPersistent() // or a named persistent store keyed to the widget
config.websiteDataStore = store

// Disable JavaScript if the user only needs a static page view
config.defaultWebpagePreferences.allowsContentJavaScript = false // optional toggle

// Prevent the page from opening new windows or triggering alerts
webView.uiDelegate = coordinator // implement and no-op window.open, alert, confirm
```

---

## Implementation Sketch

```
DeskMat/Widgets/WebFrame/
  WebFrameWidget.swift      — main SwiftUI view (NSViewRepresentable wrapper + toolbar)
  WebView.swift             — WKWebView NSViewRepresentable
  WebFrameSettings.swift    — @AppStorage keys: URL, refresh interval, JS on/off
```

Settings pane additions:
- URL text field (validated on change)
- Refresh interval picker (Live / 30s / 1m / 5m / Manual)
- JavaScript toggle
- "Clear Session Data" button

Toolbar overlay on the widget (appears on hover):
- Reload button
- Open-in-Safari button (hands off to system browser)
- Interaction-lock toggle (enables/disables mouse passthrough)

---

## Verdict

Technically straightforward — `WKWebView` is mature and well-documented. The real design challenges are:

1. **Mouse event routing** — needs a deliberate interaction model so it doesn't conflict with DeskMat's drag/drop.
2. **Performance** — live JS-heavy pages need throttling or pause-when-hidden logic.
3. **Session isolation** — use a non-default data store to keep widget sessions contained.

Best-fit use cases for users: read-only dashboards (Grafana, Linear board, simple status pages), clocks/timers from a URL, weather radar iframes. Less suitable for anything requiring heavy interaction or login flows.
