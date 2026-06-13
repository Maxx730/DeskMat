# DeskMat — Web Frame Widget Plan

A 2-cell Pro widget that loads a user-specified URL inside a live `WKWebView`,
bringing any web dashboard, status page, or read-only tool onto the dock.

---

## File layout

```
DeskMat/Widgets/WebFrame/
  WebView.swift               — NSViewRepresentable wrapping WKWebView
  WebFrameWidget.swift        — main SwiftUI widget body (cellCount = 2)
  WebFrameSettings.swift      — AppStorage key constants + refresh-interval enum
```

Four touch-points in existing files:

| File | Change |
|---|---|
| `ContentView.swift` | `@AppStorage("showWebFrameWidget")`, widget instance, `anyWidgetVisible` |
| `Settings/SettingsView.swift` | `WidgetsSettingsTab` entry (toggle + URL field + options) |
| `Core/Strings.swift` | `WebFrame` namespace |
| `Core/AppEnums.swift` | `WebFrameRefreshInterval` enum |

---

## Phase 1 — Core WebView wrapper and skeleton widget

Goal: a widget that renders a URL with no interaction model yet. Proves the
WKWebView embedding works at the correct widget dimensions.

### 1a — `AppEnums.swift`: add refresh interval enum

```swift
enum WebFrameRefreshInterval: String, CaseIterable {
    case live    = "Live"
    case sec30   = "30s"
    case min1    = "1 min"
    case min5    = "5 min"
    case manual  = "Manual"

    var seconds: TimeInterval? {
        switch self {
        case .live:   return 5
        case .sec30:  return 30
        case .min1:   return 60
        case .min5:   return 300
        case .manual: return nil
        }
    }
}
```

### 1b — `WebFrameSettings.swift`

Central home for all `@AppStorage` keys so nothing is stringly-typed across files.

```swift
import Foundation

enum WebFrameSettings {
    static let urlKey              = "webFrameURL"
    static let refreshIntervalKey  = "webFrameRefreshInterval"
    static let jsEnabledKey        = "webFrameJSEnabled"
    static let interactiveModeKey  = "webFrameInteractive"
}
```

### 1c — `WebView.swift`

```swift
import WebKit
import SwiftUI

struct WebView: NSViewRepresentable {
    let url: URL
    let jsEnabled: Bool
    let dataStore: WKWebsiteDataStore

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = dataStore
        config.defaultWebpagePreferences.allowsContentJavaScript = jsEnabled

        // Inject a wide viewport so mobile-first pages don't reflow at widget width
        let viewportScript = WKUserScript(
            source: """
                var m = document.querySelector('meta[name=viewport]');
                if (m) m.setAttribute('content','width=1200,initial-scale=1');
            """,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(viewportScript)

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator   // suppress window.open / alerts
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard webView.url?.absoluteString != url.absoluteString else { return }
        webView.load(URLRequest(url: url))
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        // Suppress alert(), confirm(), window.open() — none are useful in a widget
        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
            completionHandler()
        }
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? { nil }
    }
}
```

### 1d — `WebFrameWidget.swift` (skeleton)

```swift
import SwiftUI
import WebKit

struct WebFrameWidget: View {
    static let cellCount = 2

    @AppStorage(WebFrameSettings.urlKey)             private var rawURL      = "https://example.com"
    @AppStorage(WebFrameSettings.refreshIntervalKey) private var refreshInterval: WebFrameRefreshInterval = .manual
    @AppStorage(WebFrameSettings.jsEnabledKey)       private var jsEnabled   = true
    @AppStorage("showLabels")                        private var showLabels  = true

    // One persistent isolated data store per app launch (not shared with Safari
    // or any other widget instance). Using nonPersistent here; swap to a named
    // persistent store in Phase 4 if saved sessions are desired.
    private let dataStore = WKWebsiteDataStore.nonPersistent()

    private var url: URL? { URL(string: rawURL) }

    var body: some View {
        VStack(spacing: 10) {
            DockWidget(cells: Self.cellCount, isLoading: false, onRefresh: nil) {
                if let url {
                    WebView(url: url, jsEnabled: jsEnabled, dataStore: dataStore)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    Text(Strings.WebFrame.invalidURL)
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .padding(8)
                }
            }
            if showLabels {
                Text(Strings.WebFrame.widgetLabel)
                    .font(.caption2)
                    .lineLimit(1)
                    .frame(width: DockWidget<EmptyView>.width(for: Self.cellCount))
            }
        }
        // Phase 3: add .task for refresh interval loop
    }
}
```

**Deliverable:** Widget renders a URL. No toolbar, no settings wiring yet. Can be
temporarily hardcoded to a test URL to verify rendering.

---

## Phase 2 — Hover toolbar (reload / open-in-Safari / interaction lock)

The dock's mouse event routing is straightforward — widgets are not draggable items
so `WKWebView` already receives clicks by default. The toolbar provides user control
over the interaction mode and quick actions.

### 2a — Interaction lock overlay in `WebView.swift`

Add an `isInteractive: Bool` parameter. When `false`, a transparent `NSView` cover
sits on top of the web view and absorbs all mouse events, making it a display-only
panel.

```swift
// Inside makeNSView, after creating webView:
if !isInteractive {
    let cover = NSView()
    cover.translatesAutoresizingMaskIntoConstraints = false
    webView.addSubview(cover)
    NSLayoutConstraint.activate([
        cover.leadingAnchor.constraint(equalTo: webView.leadingAnchor),
        cover.trailingAnchor.constraint(equalTo: webView.trailingAnchor),
        cover.topAnchor.constraint(equalTo: webView.topAnchor),
        cover.bottomAnchor.constraint(equalTo: webView.bottomAnchor),
    ])
}
```

When switching `isInteractive`, the cover is added/removed in `updateNSView`.

### 2b — Toolbar overlay in `WebFrameWidget.swift`

```swift
// Wrap the DockWidget content in a ZStack with an overlay on hover:
@State private var isHovering = false
@AppStorage(WebFrameSettings.interactiveModeKey) private var isInteractive = false

// In body, replace the DockWidget content area:
ZStack(alignment: .topTrailing) {
    WebView(url: url, jsEnabled: jsEnabled, dataStore: dataStore, isInteractive: isInteractive)
        .clipShape(RoundedRectangle(cornerRadius: 8))

    if isHovering {
        HStack(spacing: 6) {
            // Reload
            toolbarButton(systemImage: "arrow.clockwise") {
                reload()
            }
            // Open in Safari
            toolbarButton(systemImage: "safari") {
                NSWorkspace.shared.open(url)
            }
            // Interaction lock
            toolbarButton(systemImage: isInteractive ? "hand.raised.fill" : "hand.raised") {
                isInteractive.toggle()
            }
        }
        .padding(4)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
        .padding(6)
        .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .topTrailing)))
    }
}
.onHover { isHovering = $0 }
.animation(.easeInOut(duration: 0.15), value: isHovering)
```

`toolbarButton` is a small private helper returning a plain-style `Button` with an
SF Symbol, matching the style of the clock/chevron buttons elsewhere in the codebase.

### 2c — Reload bridge

`WKWebView` needs to be reachable from SwiftUI to call `.reload()`. Use a simple
`@State var reloadEpoch: Int` incremented on button tap; pass it into `WebView` and
call `webView.reload()` in `updateNSView` when the value changes.

**Deliverable:** Widget shows a hover toolbar. Interaction lock prevents accidental
clicks. Open-in-Safari hands off to the system browser. Reload works.

---

## Phase 3 — Settings wiring and ContentView integration

### 3a — `Strings.swift`: add `WebFrame` namespace

```swift
enum WebFrame {
    static let widgetLabel   = "Web Frame"
    static let invalidURL    = "Invalid URL"
    static let settingsLabel = "Show Web Frame Widget"
    static let urlField      = "URL"
    static let clearSession  = "Clear Session Data"
    static let jsToggle      = "Enable JavaScript"
    static let refreshLabel  = "Refresh"
}
```

### 3b — `ContentView.swift`

Three additions:

```swift
// 1. New @AppStorage property alongside the others:
@AppStorage("showWebFrameWidget") private var showWebFrameWidget = false

// 2. After the EveWidget block:
if entitlements.isPro && showWebFrameWidget {
    WebFrameWidget()
}

// 3. Update anyWidgetVisible:
private var anyWidgetVisible: Bool {
    showTestWidget || (entitlements.isPro && (showWeatherWidget || showImageWidget ||
        showLEDBoard || showClockWidget || showSystemWidget || showEveWidget ||
        showWebFrameWidget))
}
```

### 3c — `SettingsView.swift`: add to `WidgetsSettingsTab`

New `@AppStorage` properties on `WidgetsSettingsTab`:

```swift
@AppStorage("showWebFrameWidget")            private var showWebFrameWidget      = false
@AppStorage(WebFrameSettings.urlKey)         private var webFrameURL             = "https://example.com"
@AppStorage(WebFrameSettings.refreshIntervalKey) private var webFrameRefresh: WebFrameRefreshInterval = .manual
@AppStorage(WebFrameSettings.jsEnabledKey)   private var webFrameJSEnabled       = true
```

Settings section (after the Eve section):

```swift
Section {
    Toggle(isOn: $showWebFrameWidget) {
        proLabel(Strings.WebFrame.settingsLabel, isPro: license.isPro)
    }
    .disabled(!license.isPro)

    if showWebFrameWidget && license.isPro {
        TextField(Strings.WebFrame.urlField, text: $webFrameURL)
            .textFieldStyle(.roundedBorder)
            .autocorrectionDisabled()

        Picker(Strings.WebFrame.refreshLabel, selection: $webFrameRefresh) {
            ForEach(WebFrameRefreshInterval.allCases, id: \.self) { interval in
                Text(interval.rawValue).tag(interval)
            }
        }

        Toggle(Strings.WebFrame.jsToggle, isOn: $webFrameJSEnabled)

        Button(Strings.WebFrame.clearSession, role: .destructive) {
            clearWebFrameSession()
        }
    }
}
```

`clearWebFrameSession()` calls `WKWebsiteDataStore.default().removeData(...)` or,
once Phase 4 switches to a named persistent store, removes data from that store.

### 3d — Reset to defaults in `SettingsView.swift`

Add to the `resetDefaults()` function:

```swift
ud.set(false,                                      forKey: "showWebFrameWidget")
ud.set("https://example.com",                      forKey: WebFrameSettings.urlKey)
ud.set(WebFrameRefreshInterval.manual.rawValue,    forKey: WebFrameSettings.refreshIntervalKey)
ud.set(true,                                       forKey: WebFrameSettings.jsEnabledKey)
ud.set(false,                                      forKey: WebFrameSettings.interactiveModeKey)
```

**Deliverable:** Widget appears in the dock when toggled on in Settings. URL,
refresh interval, JS toggle, and Clear Session are all accessible from the
Widgets settings tab.

---

## Phase 4 — Refresh loop, pause-when-hidden, persistent session

### 4a — Refresh loop in `WebFrameWidget.swift`

Mirror the EveWidget's `Task`-based polling loop:

```swift
.task(id: refreshInterval) {
    guard let interval = refreshInterval.seconds else { return }
    while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(interval))
        guard !Task.isCancelled else { return }
        reloadEpoch += 1   // triggers reload in WebView.updateNSView
    }
}
```

`Live` mode (5s) keeps the page refreshed for dashboards that don't auto-update.
`Manual` disables the loop entirely.

### 4b — Pause when DeskMat is hidden

`WKWebView` keeps running JS timers when off-screen. Suspend activity when the
dock panel hides:

```swift
.onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
    webViewRef?.pauseAllMediaPlayback(completionHandler: {})
    // For full suspension (heavy dashboards): stopLoading + re-load on reactivate
}
```

A lightweight approach: just throttle the `reloadEpoch` timer to 0 while the
app is hidden, resuming on `didBecomeActiveNotification`.

### 4c — Persistent session (optional, user opt-in)

The Phase 1 skeleton uses `WKWebsiteDataStore.nonPersistent()`, meaning login
sessions reset on every launch. For users who need persistent logins (Grafana, etc.),
swap to a named persistent store:

```swift
// Keyed to the widget so it never shares cookies with Safari or other widgets
private static let persistentStore = WKWebsiteDataStore(forIdentifier: UUID(uuidString: "com.deskmat.webframe")!)
```

Wire a "Keep me logged in" toggle in Settings to switch between persistent and
non-persistent stores. `clearWebFrameSession()` must clear the persistent store's
data via `removeData(ofTypes:modifiedSince:completionHandler:)`.

**Deliverable:** Widget auto-refreshes at the configured interval, pauses when
DeskMat is hidden, and optionally maintains login sessions across launches.

---

## Acceptance criteria

- [ ] Widget renders any valid HTTPS URL at 2-cell width without crashes
- [ ] Invalid or empty URL shows the fallback "Invalid URL" message
- [ ] Hover toolbar appears and dismisses with smooth animation
- [ ] Reload button reloads the current page without a full WKWebView recreation
- [ ] Open in Safari opens the current page in the system browser
- [ ] Interaction lock prevents all mouse events reaching the web view when off
- [ ] Interaction lock allows scroll, click, and form input when on
- [ ] Refresh interval loop fires at the correct cadence (verified manually with a timestamp page)
- [ ] Widget is Pro-gated: does not appear in ContentView or Settings without `license.isPro`
- [ ] Settings: URL field, refresh picker, JS toggle, Clear Session all work
- [ ] Clear Session removes cookies and local storage (verified by logging out of a site, clearing, confirming logged-out state persists on next load)
- [ ] No cookies shared between the web frame's data store and Safari
- [ ] App does not crash when the URL field is left blank
