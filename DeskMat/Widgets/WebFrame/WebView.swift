import WebKit
import SwiftUI

private final class EventBlockingView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { self }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {}
    override func mouseDragged(with event: NSEvent) {}
    override func scrollWheel(with event: NSEvent) {}
    override func rightMouseDown(with event: NSEvent) {}
}

struct WebView: NSViewRepresentable {
    let url: URL
    let jsEnabled: Bool
    let dataStore: WKWebsiteDataStore
    var reloadEpoch: Int = 0
    var isInteractive: Bool = false

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = dataStore
        config.defaultWebpagePreferences.allowsContentJavaScript = jsEnabled

        // Set viewport to match the exact widget canvas (128 × 64 pt).
        // Pages targeting this widget should design to those CSS pixel dimensions.
        let viewportScript = WKUserScript(
            source: """
                var m = document.querySelector('meta[name=viewport]');
                if (m) {
                    m.setAttribute('content', 'width=128,height=64,initial-scale=1');
                } else {
                    var meta = document.createElement('meta');
                    meta.name = 'viewport';
                    meta.content = 'width=128,height=64,initial-scale=1';
                    document.head.appendChild(meta);
                }
            """,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(viewportScript)

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator

        // clipShape() on NSViewRepresentable only clips the SwiftUI layer —
        // the NSView renders its own content independently and ignores it.
        // Corner radius must be set at the CALayer level to actually clip the page.
        webView.wantsLayer = true
        webView.layer?.cornerRadius = 10
        webView.layer?.masksToBounds = true

        let cover = EventBlockingView()
        cover.translatesAutoresizingMaskIntoConstraints = false
        webView.addSubview(cover)
        NSLayoutConstraint.activate([
            cover.leadingAnchor.constraint(equalTo: webView.leadingAnchor),
            cover.trailingAnchor.constraint(equalTo: webView.trailingAnchor),
            cover.topAnchor.constraint(equalTo: webView.topAnchor),
            cover.bottomAnchor.constraint(equalTo: webView.bottomAnchor),
        ])
        context.coordinator.cover = cover

        context.coordinator.lastLoadedURL = url
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.cover?.isHidden = isInteractive

        if context.coordinator.lastReloadEpoch != reloadEpoch {
            context.coordinator.lastReloadEpoch = reloadEpoch
            webView.reload()
            return
        }
        guard context.coordinator.lastLoadedURL != url else { return }
        context.coordinator.lastLoadedURL = url
        webView.load(URLRequest(url: url))
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var lastReloadEpoch: Int = 0
        var lastLoadedURL: URL? = nil
        fileprivate weak var cover: EventBlockingView?

        // Suppress alert(), confirm(), prompt() — none are useful in a widget context.
        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
            completionHandler()
        }

        func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
            completionHandler(false)
        }

        func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String,
                     defaultText: String?, initiatedByFrame frame: WKFrameInfo,
                     completionHandler: @escaping (String?) -> Void) {
            completionHandler(nil)
        }

        // Suppress window.open() and target="_blank" link navigation.
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? { nil }
    }
}
