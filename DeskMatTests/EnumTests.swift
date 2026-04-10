import Testing
import Foundation
@testable import DeskMat

// MARK: - HoverSize Enum Tests

struct HoverSizeTests {

    @Test func allCasesContainsThreeCases() {
        #expect(HoverSize.allCases.count == 3)
    }

    @Test func rawValuesMatchDisplayNames() {
        #expect(HoverSize.small.rawValue == "Small")
        #expect(HoverSize.medium.rawValue == "Medium")
        #expect(HoverSize.large.rawValue == "Large")
    }

    @Test func scaleValuesAreCorrect() {
        #expect(HoverSize.small.scale == 1.2)
        #expect(HoverSize.medium.scale == 1.5)
        #expect(HoverSize.large.scale == 1.8)
    }

    @Test func initFromRawValue() {
        #expect(HoverSize(rawValue: "Small") == .small)
        #expect(HoverSize(rawValue: "Medium") == .medium)
        #expect(HoverSize(rawValue: "Large") == .large)
        #expect(HoverSize(rawValue: "Invalid") == nil)
    }
}

// MARK: - HoverAnimation Enum Tests

struct HoverAnimationTests {

    @Test func allCasesContainsSixCases() {
        #expect(HoverAnimation.allCases.count == 6)
    }

    @Test func rawValuesMatchDisplayNames() {
        #expect(HoverAnimation.bounce.rawValue == "Bounce")
        #expect(HoverAnimation.pulse.rawValue == "Pulse")
        #expect(HoverAnimation.jiggle.rawValue == "Jiggle")
        #expect(HoverAnimation.pop.rawValue == "Pop")
        #expect(HoverAnimation.shine.rawValue == "Shine")
        #expect(HoverAnimation.none.rawValue == "None")
    }

    @Test func initFromRawValue() {
        #expect(HoverAnimation(rawValue: "Bounce") == .bounce)
        #expect(HoverAnimation(rawValue: "Pulse") == .pulse)
        #expect(HoverAnimation(rawValue: "Jiggle") == .jiggle)
        #expect(HoverAnimation(rawValue: "Pop") == .pop)
        #expect(HoverAnimation(rawValue: "Shine") == .shine)
        #expect(HoverAnimation(rawValue: "None") == HoverAnimation.none)
        #expect(HoverAnimation(rawValue: "Invalid") == nil)
    }
}

// MARK: - DockPosition Enum Tests

struct DockPositionTests {

    @Test func allCasesContainsTwoCases() {
        #expect(DockPosition.allCases.count == 2)
    }

    @Test func rawValuesMatchDisplayNames() {
        #expect(DockPosition.bottom.rawValue == "Bottom")
        #expect(DockPosition.top.rawValue == "Top")
    }

    @Test func initFromRawValue() {
        #expect(DockPosition(rawValue: "Bottom") == .bottom)
        #expect(DockPosition(rawValue: "Top") == .top)
        #expect(DockPosition(rawValue: "Invalid") == nil)
    }
}

// MARK: - AppearanceMode Enum Tests

struct AppearanceModeTests {

    @Test func allCasesContainsThreeCases() {
        #expect(AppearanceMode.allCases.count == 3)
    }

    @Test func rawValuesMatchDisplayNames() {
        #expect(AppearanceMode.system.rawValue == "System")
        #expect(AppearanceMode.light.rawValue == "Light")
        #expect(AppearanceMode.dark.rawValue == "Dark")
    }

    @Test func initFromRawValue() {
        #expect(AppearanceMode(rawValue: "System") == .system)
        #expect(AppearanceMode(rawValue: "Light") == .light)
        #expect(AppearanceMode(rawValue: "Dark") == .dark)
        #expect(AppearanceMode(rawValue: "Invalid") == nil)
    }
}

// MARK: - DockBackground Enum Tests

struct DockBackgroundEnumTests {

    @Test func allCasesContainsThreeCases() {
        #expect(DockBackground.allCases.count == 3)
    }

    @Test func rawValuesMatchDisplayNames() {
        #expect(DockBackground.system.rawValue == "System")
        #expect(DockBackground.color.rawValue == "Color")
        #expect(DockBackground.transparent.rawValue == "Transparent")
    }

    @Test func initFromRawValue() {
        #expect(DockBackground(rawValue: "System") == .system)
        #expect(DockBackground(rawValue: "Color") == .color)
        #expect(DockBackground(rawValue: "Transparent") == .transparent)
        #expect(DockBackground(rawValue: "Invalid") == nil)
    }
}

// MARK: - VisualEffect Enum Tests

struct VisualEffectTests {

    @Test func allCasesContainsEightCases() {
        #expect(VisualEffect.allCases.count == 8)
    }

    @Test func rawValuesMatchDisplayNames() {
        #expect(VisualEffect.none.rawValue == "None")
        #expect(VisualEffect.scanlineWiggle.rawValue == "Scanline Wiggle")
        #expect(VisualEffect.hueDrift.rawValue == "Hue Drift")
        #expect(VisualEffect.filmGrain.rawValue == "Film Grain")
        #expect(VisualEffect.pixelate.rawValue == "Pixelate")
        #expect(VisualEffect.softBloom.rawValue == "Soft Bloom")
        #expect(VisualEffect.heatShimmer.rawValue == "Heat Shimmer")
        #expect(VisualEffect.oldFilm.rawValue == "Old Film")
    }

    @Test func initFromRawValue() {
        #expect(VisualEffect(rawValue: "None") == VisualEffect.none)
        #expect(VisualEffect(rawValue: "Scanline Wiggle") == .scanlineWiggle)
        #expect(VisualEffect(rawValue: "Hue Drift") == .hueDrift)
        #expect(VisualEffect(rawValue: "Film Grain") == .filmGrain)
        #expect(VisualEffect(rawValue: "Pixelate") == .pixelate)
        #expect(VisualEffect(rawValue: "Soft Bloom") == .softBloom)
        #expect(VisualEffect(rawValue: "Heat Shimmer") == .heatShimmer)
        #expect(VisualEffect(rawValue: "Old Film") == .oldFilm)
        #expect(VisualEffect(rawValue: "Invalid") == nil)
    }
}

// MARK: - HideAnimation Enum Tests

struct HideAnimationTests {

    @Test func allCasesContainsTwoCases() {
        #expect(HideAnimation.allCases.count == 2)
    }

    @Test func rawValuesMatchDisplayNames() {
        #expect(HideAnimation.fade.rawValue == "Fade")
        #expect(HideAnimation.slide.rawValue == "Slide")
    }

    @Test func initFromRawValue() {
        #expect(HideAnimation(rawValue: "Fade") == .fade)
        #expect(HideAnimation(rawValue: "Slide") == .slide)
        #expect(HideAnimation(rawValue: "Invalid") == nil)
    }
}

// MARK: - SystemMetric Enum Tests

struct SystemMetricTests {

    @Test func allCasesContainsThreeCases() {
        #expect(SystemMetric.allCases.count == 3)
    }

    @Test func rawValuesMatchDisplayNames() {
        #expect(SystemMetric.cpu.rawValue == "CPU")
        #expect(SystemMetric.ram.rawValue == "RAM")
        #expect(SystemMetric.network.rawValue == "Network")
    }

    @Test func initFromRawValue() {
        #expect(SystemMetric(rawValue: "CPU") == .cpu)
        #expect(SystemMetric(rawValue: "RAM") == .ram)
        #expect(SystemMetric(rawValue: "Network") == .network)
        #expect(SystemMetric(rawValue: "Invalid") == nil)
    }

    @Test func cpuCellCountIsOne() {
        #expect(SystemMetric.cpu.cellCount == 1)
    }

    @Test func ramCellCountIsTwo() {
        #expect(SystemMetric.ram.cellCount == 2)
    }

    @Test func networkCellCountIsTwo() {
        #expect(SystemMetric.network.cellCount == 2)
    }
}

// MARK: - ActivationResult Enum Tests

struct ActivationResultTests {

    @Test func allCasesExist() {
        let results: [ActivationResult] = [.success, .invalid, .alreadyActive, .error("test")]
        #expect(results.count == 4)
    }

    @Test func casesAreDistinct() {
        if case .success      = ActivationResult.success      { } else { Issue.record("expected .success") }
        if case .invalid      = ActivationResult.invalid      { } else { Issue.record("expected .invalid") }
        if case .alreadyActive = ActivationResult.alreadyActive { } else { Issue.record("expected .alreadyActive") }
        if case .error        = ActivationResult.error("msg") { } else { Issue.record("expected .error") }
    }

    @Test func errorCarriesMessage() {
        if case .error(let msg) = ActivationResult.error("network failure") {
            #expect(msg == "network failure")
        } else {
            Issue.record("expected .error with message")
        }
    }
}

// MARK: - DeactivationResult Enum Tests

struct DeactivationResultTests {

    @Test func allCasesExist() {
        let results: [DeactivationResult] = [.success, .error("test")]
        #expect(results.count == 2)
    }

    @Test func errorCarriesMessage() {
        if case .error(let msg) = DeactivationResult.error("no key found") {
            #expect(msg == "no key found")
        } else {
            Issue.record("expected .error with message")
        }
    }
}
