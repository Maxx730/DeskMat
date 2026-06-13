import Testing
import Foundation
@testable import DeskMat

// MARK: - WebFrameRefreshInterval

struct WebFrameRefreshIntervalTests {

    @Test func allCasesContainsFiveCases() {
        #expect(WebFrameRefreshInterval.allCases.count == 5)
    }

    @Test func rawValuesAreStable() {
        #expect(WebFrameRefreshInterval.live.rawValue   == "Live")
        #expect(WebFrameRefreshInterval.sec30.rawValue  == "30s")
        #expect(WebFrameRefreshInterval.min1.rawValue   == "1 min")
        #expect(WebFrameRefreshInterval.min5.rawValue   == "5 min")
        #expect(WebFrameRefreshInterval.manual.rawValue == "Manual")
    }

    @Test func initFromRawValue() {
        #expect(WebFrameRefreshInterval(rawValue: "Live")   == .live)
        #expect(WebFrameRefreshInterval(rawValue: "30s")    == .sec30)
        #expect(WebFrameRefreshInterval(rawValue: "1 min")  == .min1)
        #expect(WebFrameRefreshInterval(rawValue: "5 min")  == .min5)
        #expect(WebFrameRefreshInterval(rawValue: "Manual") == .manual)
        #expect(WebFrameRefreshInterval(rawValue: "Invalid") == nil)
    }

    // seconds drives the refresh loop — wrong values here break cadence silently
    @Test func liveIntervalIsFiveSeconds() {
        #expect(WebFrameRefreshInterval.live.seconds == 5)
    }

    @Test func sec30IntervalIsThirtySeconds() {
        #expect(WebFrameRefreshInterval.sec30.seconds == 30)
    }

    @Test func min1IntervalIsSixtySeconds() {
        #expect(WebFrameRefreshInterval.min1.seconds == 60)
    }

    @Test func min5IntervalIsThreeHundredSeconds() {
        #expect(WebFrameRefreshInterval.min5.seconds == 300)
    }

    // manual must return nil — the refresh loop guard returns early on nil,
    // so any non-nil value here would cause unintended background reloading
    @Test func manualIntervalIsNil() {
        #expect(WebFrameRefreshInterval.manual.seconds == nil)
    }

    @Test func allTimedCasesHavePositiveInterval() {
        let timed = WebFrameRefreshInterval.allCases.filter { $0 != .manual }
        for interval in timed {
            let seconds = interval.seconds
            #expect(seconds != nil, "Expected non-nil seconds for \(interval)")
            #expect((seconds ?? 0) > 0, "Expected positive interval for \(interval)")
        }
    }

    @Test func intervalsAreInAscendingOrder() {
        let ordered: [WebFrameRefreshInterval] = [.live, .sec30, .min1, .min5]
        let seconds = ordered.compactMap { $0.seconds }
        #expect(seconds == seconds.sorted())
    }
}

// MARK: - WebFrameSettings

struct WebFrameSettingsTests {

    @Test func allKeysAreNonEmpty() {
        #expect(!WebFrameSettings.urlKey.isEmpty)
        #expect(!WebFrameSettings.refreshIntervalKey.isEmpty)
        #expect(!WebFrameSettings.jsEnabledKey.isEmpty)
        #expect(!WebFrameSettings.interactiveModeKey.isEmpty)
        #expect(!WebFrameSettings.persistSessionKey.isEmpty)
    }

    // Duplicate keys would silently cause one setting to overwrite another
    @Test func allKeysAreUnique() {
        let keys = [
            WebFrameSettings.urlKey,
            WebFrameSettings.refreshIntervalKey,
            WebFrameSettings.jsEnabledKey,
            WebFrameSettings.interactiveModeKey,
            WebFrameSettings.persistSessionKey,
        ]
        #expect(Set(keys).count == keys.count)
    }

    @Test func keyValuesAreStable() {
        #expect(WebFrameSettings.urlKey             == "webFrameURL")
        #expect(WebFrameSettings.refreshIntervalKey == "webFrameRefreshInterval")
        #expect(WebFrameSettings.jsEnabledKey       == "webFrameJSEnabled")
        #expect(WebFrameSettings.interactiveModeKey == "webFrameInteractive")
        #expect(WebFrameSettings.persistSessionKey  == "webFramePersistSession")
    }
}

// MARK: - WebFrameWidget

struct WebFrameWidgetTests {

    @Test func cellCountIsTwo() {
        #expect(WebFrameWidget.cellCount == 2)
    }
}

// MARK: - WebView.Coordinator

struct WebViewCoordinatorTests {

    @Test func initialReloadEpochIsZero() {
        let coordinator = WebView.Coordinator()
        #expect(coordinator.lastReloadEpoch == 0)
    }

    @Test func initialLastLoadedURLIsNil() {
        let coordinator = WebView.Coordinator()
        #expect(coordinator.lastLoadedURL == nil)
    }

    @Test func lastLoadedURLCanBeSet() {
        let coordinator = WebView.Coordinator()
        let url = URL(string: "https://example.com")!
        coordinator.lastLoadedURL = url
        #expect(coordinator.lastLoadedURL == url)
    }

    @Test func reloadEpochCanBeIncremented() {
        let coordinator = WebView.Coordinator()
        coordinator.lastReloadEpoch = 3
        #expect(coordinator.lastReloadEpoch == 3)
    }
}
