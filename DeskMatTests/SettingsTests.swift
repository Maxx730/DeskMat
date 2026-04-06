import Testing
import Foundation
import AppKit
import SwiftUI
@testable import DeskMat

// MARK: - General Settings Tests

@Suite(.serialized)
struct SettingsTests {

    @Test func showLabelsDefaultsToTrue() {
        let defaults = UserDefaults.standard
        let existing = defaults.object(forKey: "showLabels")
        defer {
            if let existing { defaults.set(existing, forKey: "showLabels") }
            else { defaults.removeObject(forKey: "showLabels") }
        }

        defaults.removeObject(forKey: "showLabels")
        #expect(defaults.object(forKey: "showLabels") == nil)
    }

    @Test func hoverSizeDefaultsToSmall() {
        let defaults = UserDefaults.standard
        let existing = defaults.object(forKey: "hoverSize")
        defer {
            if let existing { defaults.set(existing, forKey: "hoverSize") }
            else { defaults.removeObject(forKey: "hoverSize") }
        }

        defaults.removeObject(forKey: "hoverSize")
        #expect(defaults.object(forKey: "hoverSize") == nil)
    }

    @Test func showLabelsPersistedToUserDefaults() {
        let defaults = UserDefaults.standard
        let existing = defaults.object(forKey: "showLabels")
        defer {
            if let existing { defaults.set(existing, forKey: "showLabels") }
            else { defaults.removeObject(forKey: "showLabels") }
        }

        defaults.set(false, forKey: "showLabels")
        #expect(defaults.bool(forKey: "showLabels") == false)

        defaults.set(true, forKey: "showLabels")
        #expect(defaults.bool(forKey: "showLabels") == true)
    }

    @Test func hoverSizePersistedToUserDefaults() {
        let defaults = UserDefaults.standard
        let existing = defaults.object(forKey: "hoverSize")
        defer {
            if let existing { defaults.set(existing, forKey: "hoverSize") }
            else { defaults.removeObject(forKey: "hoverSize") }
        }

        defaults.set(HoverSize.medium.rawValue, forKey: "hoverSize")
        #expect(defaults.string(forKey: "hoverSize") == "Medium")

        defaults.set(HoverSize.large.rawValue, forKey: "hoverSize")
        #expect(defaults.string(forKey: "hoverSize") == "Large")
    }
}

// MARK: - Additional Settings Tests

@Suite(.serialized)
struct AdditionalSettingsTests {

    @Test func hoverAnimationDefaultsToBounce() {
        let defaults = UserDefaults.standard
        let existing = defaults.object(forKey: "hoverAnimation")
        defer {
            if let existing { defaults.set(existing, forKey: "hoverAnimation") }
            else { defaults.removeObject(forKey: "hoverAnimation") }
        }

        defaults.removeObject(forKey: "hoverAnimation")
        #expect(defaults.object(forKey: "hoverAnimation") == nil)
    }

    @Test func hoverAnimationPersistedToUserDefaults() {
        let defaults = UserDefaults.standard
        let existing = defaults.object(forKey: "hoverAnimation")
        defer {
            if let existing { defaults.set(existing, forKey: "hoverAnimation") }
            else { defaults.removeObject(forKey: "hoverAnimation") }
        }

        defaults.set(HoverAnimation.jiggle.rawValue, forKey: "hoverAnimation")
        #expect(defaults.string(forKey: "hoverAnimation") == "Jiggle")

        defaults.set(HoverAnimation.none.rawValue, forKey: "hoverAnimation")
        #expect(defaults.string(forKey: "hoverAnimation") == "None")
    }

    @Test func dockPositionDefaultsToBottom() {
        let defaults = UserDefaults.standard
        let existing = defaults.object(forKey: "dockPosition")
        defer {
            if let existing { defaults.set(existing, forKey: "dockPosition") }
            else { defaults.removeObject(forKey: "dockPosition") }
        }

        defaults.removeObject(forKey: "dockPosition")
        #expect(defaults.object(forKey: "dockPosition") == nil)
    }

    @Test func dockPositionPersistedToUserDefaults() {
        let defaults = UserDefaults.standard
        let existing = defaults.object(forKey: "dockPosition")
        defer {
            if let existing { defaults.set(existing, forKey: "dockPosition") }
            else { defaults.removeObject(forKey: "dockPosition") }
        }

        defaults.set(DockPosition.top.rawValue, forKey: "dockPosition")
        #expect(defaults.string(forKey: "dockPosition") == "Top")

        defaults.set(DockPosition.bottom.rawValue, forKey: "dockPosition")
        #expect(defaults.string(forKey: "dockPosition") == "Bottom")
    }

    @Test func dockOffsetDefaultsToZero() {
        let defaults = UserDefaults.standard
        let existing = defaults.object(forKey: "dockOffset")
        defer {
            if let existing { defaults.set(existing, forKey: "dockOffset") }
            else { defaults.removeObject(forKey: "dockOffset") }
        }

        defaults.removeObject(forKey: "dockOffset")
        #expect(defaults.integer(forKey: "dockOffset") == 0)
    }

    @Test func dockOffsetPersistedToUserDefaults() {
        let defaults = UserDefaults.standard
        let existing = defaults.object(forKey: "dockOffset")
        defer {
            if let existing { defaults.set(existing, forKey: "dockOffset") }
            else { defaults.removeObject(forKey: "dockOffset") }
        }

        defaults.set(25, forKey: "dockOffset")
        #expect(defaults.integer(forKey: "dockOffset") == 25)

        defaults.set(-10, forKey: "dockOffset")
        #expect(defaults.integer(forKey: "dockOffset") == -10)
    }
}

// MARK: - Dock Background Settings Tests

@Suite(.serialized)
struct DockBackgroundSettingsTests {

    @Test func showDockBackgroundDefaultsToTrue() {
        let defaults = UserDefaults.standard
        let existing = defaults.object(forKey: "showDockBackground")
        defer {
            if let existing { defaults.set(existing, forKey: "showDockBackground") }
            else { defaults.removeObject(forKey: "showDockBackground") }
        }

        defaults.removeObject(forKey: "showDockBackground")
        #expect(defaults.object(forKey: "showDockBackground") == nil)
    }

    @Test func showDockBackgroundPersistedToUserDefaults() {
        let defaults = UserDefaults.standard
        let existing = defaults.object(forKey: "showDockBackground")
        defer {
            if let existing { defaults.set(existing, forKey: "showDockBackground") }
            else { defaults.removeObject(forKey: "showDockBackground") }
        }

        defaults.set(false, forKey: "showDockBackground")
        #expect(defaults.bool(forKey: "showDockBackground") == false)

        defaults.set(true, forKey: "showDockBackground")
        #expect(defaults.bool(forKey: "showDockBackground") == true)
    }

    @Test func dockBackgroundColorHexDefaultsToBlack() {
        let defaults = UserDefaults.standard
        let existing = defaults.object(forKey: "dockBackgroundColorHex")
        defer {
            if let existing { defaults.set(existing, forKey: "dockBackgroundColorHex") }
            else { defaults.removeObject(forKey: "dockBackgroundColorHex") }
        }

        defaults.removeObject(forKey: "dockBackgroundColorHex")
        #expect(defaults.string(forKey: "dockBackgroundColorHex") == nil)
    }

    @Test func dockBackgroundColorHexPersistedToUserDefaults() {
        let defaults = UserDefaults.standard
        let existing = defaults.object(forKey: "dockBackgroundColorHex")
        defer {
            if let existing { defaults.set(existing, forKey: "dockBackgroundColorHex") }
            else { defaults.removeObject(forKey: "dockBackgroundColorHex") }
        }

        defaults.set("#ff0000ff", forKey: "dockBackgroundColorHex")
        #expect(defaults.string(forKey: "dockBackgroundColorHex") == "#ff0000ff")

        defaults.set("#000000ff", forKey: "dockBackgroundColorHex")
        #expect(defaults.string(forKey: "dockBackgroundColorHex") == "#000000ff")
    }

    @Test func dockBackgroundColorHexDecodesStoredValue() {
        let defaults = UserDefaults.standard
        let existing = defaults.object(forKey: "dockBackgroundColorHex")
        defer {
            if let existing { defaults.set(existing, forKey: "dockBackgroundColorHex") }
            else { defaults.removeObject(forKey: "dockBackgroundColorHex") }
        }

        defaults.set("#0000ffff", forKey: "dockBackgroundColorHex")

        let hex = defaults.string(forKey: "dockBackgroundColorHex") ?? "#000000ff"
        let color = ColorUtils.fromHex(hex)
        let ns = NSColor(color).usingColorSpace(.sRGB)!

        #expect(ns.redComponent < 0.01)
        #expect(ns.greenComponent < 0.01)
        #expect(abs(ns.blueComponent - 1.0) < 0.01)
    }
}

// MARK: - Widget Settings Tests

@Suite(.serialized)
struct WidgetSettingsTests {

    @Test func showWeatherWidgetDefaultsToTrue() {
        let defaults = UserDefaults.standard
        let existing = defaults.object(forKey: "showWeatherWidget")
        defer {
            if let existing { defaults.set(existing, forKey: "showWeatherWidget") }
            else { defaults.removeObject(forKey: "showWeatherWidget") }
        }

        defaults.removeObject(forKey: "showWeatherWidget")
        #expect(defaults.object(forKey: "showWeatherWidget") == nil)
    }

    @Test func showClockWidgetDefaultsToTrue() {
        let defaults = UserDefaults.standard
        let existing = defaults.object(forKey: "showClockWidget")
        defer {
            if let existing { defaults.set(existing, forKey: "showClockWidget") }
            else { defaults.removeObject(forKey: "showClockWidget") }
        }

        defaults.removeObject(forKey: "showClockWidget")
        #expect(defaults.object(forKey: "showClockWidget") == nil)
    }

    @Test func showWeatherWidgetPersistedToUserDefaults() {
        let defaults = UserDefaults.standard
        let existing = defaults.object(forKey: "showWeatherWidget")
        defer {
            if let existing { defaults.set(existing, forKey: "showWeatherWidget") }
            else { defaults.removeObject(forKey: "showWeatherWidget") }
        }

        defaults.set(false, forKey: "showWeatherWidget")
        #expect(defaults.bool(forKey: "showWeatherWidget") == false)

        defaults.set(true, forKey: "showWeatherWidget")
        #expect(defaults.bool(forKey: "showWeatherWidget") == true)
    }

    @Test func showClockWidgetPersistedToUserDefaults() {
        let defaults = UserDefaults.standard
        let existing = defaults.object(forKey: "showClockWidget")
        defer {
            if let existing { defaults.set(existing, forKey: "showClockWidget") }
            else { defaults.removeObject(forKey: "showClockWidget") }
        }

        defaults.set(false, forKey: "showClockWidget")
        #expect(defaults.bool(forKey: "showClockWidget") == false)

        defaults.set(true, forKey: "showClockWidget")
        #expect(defaults.bool(forKey: "showClockWidget") == true)
    }

    @Test func finderDefaultDirectoryDefaultsToHome() {
        let defaults = UserDefaults.standard
        let existing = defaults.object(forKey: "finderDefaultDirectory")
        defer {
            if let existing { defaults.set(existing, forKey: "finderDefaultDirectory") }
            else { defaults.removeObject(forKey: "finderDefaultDirectory") }
        }

        defaults.removeObject(forKey: "finderDefaultDirectory")
        #expect(defaults.object(forKey: "finderDefaultDirectory") == nil)
    }

    @Test func finderDefaultDirectoryPersistedToUserDefaults() {
        let defaults = UserDefaults.standard
        let existing = defaults.object(forKey: "finderDefaultDirectory")
        defer {
            if let existing { defaults.set(existing, forKey: "finderDefaultDirectory") }
            else { defaults.removeObject(forKey: "finderDefaultDirectory") }
        }

        defaults.set("~/Desktop", forKey: "finderDefaultDirectory")
        #expect(defaults.string(forKey: "finderDefaultDirectory") == "~/Desktop")

        defaults.set("/Applications", forKey: "finderDefaultDirectory")
        #expect(defaults.string(forKey: "finderDefaultDirectory") == "/Applications")
    }
}

// MARK: - AutoHide Settings Tests

@Suite(.serialized)
struct AutoHideSettingsTests {

    @Test func autoHideDockDefaultsToFalse() {
        let defaults = UserDefaults.standard
        let existing = defaults.object(forKey: "autoHideDock")
        defer {
            if let existing { defaults.set(existing, forKey: "autoHideDock") }
            else { defaults.removeObject(forKey: "autoHideDock") }
        }

        defaults.removeObject(forKey: "autoHideDock")
        #expect(defaults.bool(forKey: "autoHideDock") == false)
    }

    @Test func autoHideDockPersistedToUserDefaults() {
        let defaults = UserDefaults.standard
        let existing = defaults.object(forKey: "autoHideDock")
        defer {
            if let existing { defaults.set(existing, forKey: "autoHideDock") }
            else { defaults.removeObject(forKey: "autoHideDock") }
        }

        defaults.set(true, forKey: "autoHideDock")
        #expect(defaults.bool(forKey: "autoHideDock") == true)

        defaults.set(false, forKey: "autoHideDock")
        #expect(defaults.bool(forKey: "autoHideDock") == false)
    }

    @Test func autoHideDockKeyIsDistinctFromOtherBoolKeys() {
        let key = "autoHideDock"
        #expect(key != "showLabels")
        #expect(key != "showWeatherWidget")
        #expect(key != "showClockWidget")
        #expect(key != "showImageWidget")
        #expect(key != "showLEDBoard")
    }
}

// MARK: - Visual Effect Settings Tests

@Suite(.serialized)
struct VisualEffectSettingsTests {

    @Test func visualEffectDefaultsToNone() {
        let defaults = UserDefaults.standard
        let existing = defaults.object(forKey: "visualEffect")
        defer {
            if let existing { defaults.set(existing, forKey: "visualEffect") }
            else { defaults.removeObject(forKey: "visualEffect") }
        }

        defaults.removeObject(forKey: "visualEffect")
        #expect(defaults.object(forKey: "visualEffect") == nil)
    }

    @Test func visualEffectPersistedToUserDefaults() {
        let defaults = UserDefaults.standard
        let existing = defaults.object(forKey: "visualEffect")
        defer {
            if let existing { defaults.set(existing, forKey: "visualEffect") }
            else { defaults.removeObject(forKey: "visualEffect") }
        }

        defaults.set(VisualEffect.scanlineWiggle.rawValue, forKey: "visualEffect")
        #expect(defaults.string(forKey: "visualEffect") == "Scanline Wiggle")
    }

    @Test func dockItemShaderIntensityDefaultsToHalf() {
        let defaults = UserDefaults.standard
        let existing = defaults.object(forKey: "dockItemShaderIntensity")
        defer {
            if let existing { defaults.set(existing, forKey: "dockItemShaderIntensity") }
            else { defaults.removeObject(forKey: "dockItemShaderIntensity") }
        }

        defaults.removeObject(forKey: "dockItemShaderIntensity")
        #expect(defaults.object(forKey: "dockItemShaderIntensity") == nil)
    }

    @Test func dockItemShaderIntensityPersistedToUserDefaults() {
        let defaults = UserDefaults.standard
        let existing = defaults.object(forKey: "dockItemShaderIntensity")
        defer {
            if let existing { defaults.set(existing, forKey: "dockItemShaderIntensity") }
            else { defaults.removeObject(forKey: "dockItemShaderIntensity") }
        }

        defaults.set(0.0, forKey: "dockItemShaderIntensity")
        #expect(abs(defaults.double(forKey: "dockItemShaderIntensity") - 0.0) < 0.001)

        defaults.set(1.0, forKey: "dockItemShaderIntensity")
        #expect(abs(defaults.double(forKey: "dockItemShaderIntensity") - 1.0) < 0.001)

        defaults.set(0.75, forKey: "dockItemShaderIntensity")
        #expect(abs(defaults.double(forKey: "dockItemShaderIntensity") - 0.75) < 0.001)
    }
}

// MARK: - HideAnimation Settings Tests

@Suite(.serialized)
struct HideAnimationSettingsTests {

    @Test func hideAnimationDefaultsToFade() {
        let defaults = UserDefaults.standard
        let existing = defaults.object(forKey: "hideAnimation")
        defer {
            if let existing { defaults.set(existing, forKey: "hideAnimation") }
            else { defaults.removeObject(forKey: "hideAnimation") }
        }

        defaults.removeObject(forKey: "hideAnimation")
        #expect(defaults.object(forKey: "hideAnimation") == nil)
    }

    @Test func hideAnimationPersistedToUserDefaults() {
        let defaults = UserDefaults.standard
        let existing = defaults.object(forKey: "hideAnimation")
        defer {
            if let existing { defaults.set(existing, forKey: "hideAnimation") }
            else { defaults.removeObject(forKey: "hideAnimation") }
        }

        defaults.set(HideAnimation.slide.rawValue, forKey: "hideAnimation")
        #expect(defaults.string(forKey: "hideAnimation") == "Slide")

        defaults.set(HideAnimation.fade.rawValue, forKey: "hideAnimation")
        #expect(defaults.string(forKey: "hideAnimation") == "Fade")
    }
}

// MARK: - System Widget Settings Tests

@Suite(.serialized)
struct SystemWidgetSettingsTests {

    @Test func showSystemWidgetDefaultsToAbsent() {
        let defaults = UserDefaults.standard
        let existing = defaults.object(forKey: "showSystemWidget")
        defer {
            if let existing { defaults.set(existing, forKey: "showSystemWidget") }
            else { defaults.removeObject(forKey: "showSystemWidget") }
        }

        defaults.removeObject(forKey: "showSystemWidget")
        #expect(defaults.object(forKey: "showSystemWidget") == nil)
    }

    @Test func showSystemWidgetPersistedToUserDefaults() {
        let defaults = UserDefaults.standard
        let existing = defaults.object(forKey: "showSystemWidget")
        defer {
            if let existing { defaults.set(existing, forKey: "showSystemWidget") }
            else { defaults.removeObject(forKey: "showSystemWidget") }
        }

        defaults.set(false, forKey: "showSystemWidget")
        #expect(defaults.bool(forKey: "showSystemWidget") == false)

        defaults.set(true, forKey: "showSystemWidget")
        #expect(defaults.bool(forKey: "showSystemWidget") == true)
    }

    @Test func sysWidgetMetricPersistedToUserDefaults() {
        let defaults = UserDefaults.standard
        let existing = defaults.object(forKey: "sysWidgetMetric")
        defer {
            if let existing { defaults.set(existing, forKey: "sysWidgetMetric") }
            else { defaults.removeObject(forKey: "sysWidgetMetric") }
        }

        defaults.set(SystemMetric.ram.rawValue, forKey: "sysWidgetMetric")
        #expect(defaults.string(forKey: "sysWidgetMetric") == "RAM")

        defaults.set(SystemMetric.network.rawValue, forKey: "sysWidgetMetric")
        #expect(defaults.string(forKey: "sysWidgetMetric") == "Network")
    }
}
