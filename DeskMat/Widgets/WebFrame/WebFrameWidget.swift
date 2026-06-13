import SwiftUI
import WebKit

struct WebFrameWidget: View {
    static let cellCount = 2

    @AppStorage(WebFrameSettings.urlKey)             private var rawURL         = "http://localhost:8080/demo-widget"
    @AppStorage(WebFrameSettings.jsEnabledKey)       private var jsEnabled      = true
    @AppStorage(WebFrameSettings.refreshIntervalKey) private var refreshInterval: WebFrameRefreshInterval = .manual
    @AppStorage(WebFrameSettings.interactiveModeKey) private var isInteractive  = false
    @AppStorage(WebFrameSettings.persistSessionKey)  private var persistSession = false
    @AppStorage("showLabels")                        private var showLabels     = true

    // Deterministic UUID keyed to this widget — never shares cookies with Safari
    // or any other app. Used only when persistSession is true.
    private static let persistentStore: WKWebsiteDataStore = {
        let id = UUID(uuidString: "DA5EBED4-F8B4-4F92-9E6A-B4CA1D59C6E7")!
        return WKWebsiteDataStore(forIdentifier: id)
    }()

    // Resolved once by makeNSView; changing persistSession mid-session takes
    // effect the next time the widget is mounted.
    private var activeDataStore: WKWebsiteDataStore {
        persistSession ? Self.persistentStore : WKWebsiteDataStore.nonPersistent()
    }

    @State private var reloadEpoch  = 0
    @State private var isHovering   = false
    @State private var isAppActive  = true

    private var url: URL? { URL(string: rawURL) }

    var body: some View {
        VStack(spacing: 10) {
            DockWidget(cells: Self.cellCount, isLoading: false) {
                ZStack(alignment: .topTrailing) {
                    if let url {
                        WebView(
                            url: url,
                            jsEnabled: jsEnabled,
                            dataStore: activeDataStore,
                            reloadEpoch: reloadEpoch,
                            isInteractive: isInteractive
                        )
                    } else {
                        Text(Strings.WebFrame.invalidURL)
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.6))
                            .multilineTextAlignment(.center)
                            .padding(8)
                    }

                    if isHovering {
                        toolbar
                            .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .topTrailing)))
                    }
                }
            }
            .onHover { isHovering = $0 }
            .animation(.easeInOut(duration: 0.15), value: isHovering)

            if showLabels {
                Text(Strings.WebFrame.widgetLabel)
                    .font(.caption2)
                    .lineLimit(1)
                    .frame(width: DockWidget<EmptyView>.width(for: Self.cellCount))
            }
        }
        .task(id: refreshInterval) {
            guard let interval = refreshInterval.seconds else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { return }
                guard isAppActive else { continue }
                reloadEpoch += 1
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            isAppActive = false
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            isAppActive = true
        }
    }

    // Called from Settings (Phase 3) to wipe the persistent store.
    static func clearSession() {
        persistentStore.removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
            modifiedSince: .distantPast
        ) {}
    }

    private var toolbar: some View {
        HStack(spacing: 4) {
            toolbarButton(systemImage: "arrow.clockwise") {
                reloadEpoch += 1
            }
            if let url {
                toolbarButton(systemImage: "safari") {
                    NSWorkspace.shared.open(url)
                }
            }
            toolbarButton(systemImage: isInteractive ? "hand.raised.fill" : "hand.raised") {
                isInteractive.toggle()
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
        .padding(6)
    }

    private func toolbarButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
