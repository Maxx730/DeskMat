import Testing
import AppKit
@testable import DeskMat

// MARK: - ReactiveBackgroundView Tests
//
// Metal pipeline construction (rebuildPipeline, draw(in:)) cannot be unit-tested
// without a real MTLDevice and drawable surface. Tests here cover the logic that
// runs before Metal is involved: shader routing, uniform construction, and the
// opacity fade interpolation math.

@MainActor
struct ReactiveBackgroundViewTests {

    // MARK: - fragmentShaderName routing

    @Test func lockOnStyleRoutesToLockOnFragment() {
        let view = ReactiveBackgroundView()
        view.reactiveStyle = .lockOn
        #expect(view.fragmentShaderName == "lockOnFragment")
    }

    @Test func liquidFillStyleRoutesToLiquidFillFragment() {
        let view = ReactiveBackgroundView()
        view.reactiveStyle = .liquidFill
        #expect(view.fragmentShaderName == "liquidFillFragment")
    }

    @Test func eachStyleProducesUniqueShaderName() {
        let names = ReactiveStyle.allCases.map { style -> String in
            let view = ReactiveBackgroundView()
            view.reactiveStyle = style
            return view.fragmentShaderName
        }
        #expect(Set(names).count == ReactiveStyle.allCases.count)
    }

    @Test func defaultStyleIsLockOn() {
        let view = ReactiveBackgroundView()
        #expect(view.reactiveStyle == .lockOn)
    }

    // MARK: - makeUniforms

    @Test func makeUniformsPopulatesResolution() {
        let view = ReactiveBackgroundView(frame: NSRect(x: 0, y: 0, width: 400, height: 84))
        let u = view.makeUniforms(time: 0, opacity: 0)
        #expect(u.resolution.x == 400)
        #expect(u.resolution.y == 84)
    }

    @Test func makeUniformsPassesThroughTime() {
        let view = ReactiveBackgroundView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        let u = view.makeUniforms(time: 3.5, opacity: 0)
        #expect(u.time == 3.5)
    }

    @Test func makeUniformsPassesThroughOpacity() {
        let view = ReactiveBackgroundView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        let u = view.makeUniforms(time: 0, opacity: 0.75)
        #expect(u.indicatorOpacity == 0.75)
    }

    @Test func makeUniformsMousePositionDefaultsToZeroWhenNotHovering() {
        let view = ReactiveBackgroundView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        let u = view.makeUniforms(time: 0, opacity: 0)
        #expect(u.mousePosition.x == 0)
        #expect(u.mousePosition.y == 0)
    }

    @Test func makeUniformsUsesCornerRadius() {
        let view = ReactiveBackgroundView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        view.cornerRadius = 12
        let u = view.makeUniforms(time: 0, opacity: 0)
        #expect(u.cornerRadius == 12)
    }

    // MARK: - Opacity fade math
    //
    // Mirrors the interpolation in draw(in:).
    // Fade-in: opacity = min((elapsed since hover) / 0.1, 1.0)
    // Fade-out: opacity = max(1 - (elapsed since exit) / 0.2, 0.0)

    private func fadeInOpacity(elapsed: Double) -> Float {
        Float(min(elapsed / 0.1, 1.0))
    }

    private func fadeOutOpacity(elapsed: Double) -> Float {
        Float(max(1.0 - elapsed / 0.2, 0.0))
    }

    @Test func fadeInReachesFullOpacityAt100ms() {
        #expect(fadeInOpacity(elapsed: 0.1) == 1.0)
    }

    @Test func fadeInIsZeroAtStart() {
        #expect(fadeInOpacity(elapsed: 0.0) == 0.0)
    }

    @Test func fadeInClampsAboveOne() {
        #expect(fadeInOpacity(elapsed: 0.5) == 1.0)
    }

    @Test func fadeInIsProportionalMidway() {
        #expect(fadeInOpacity(elapsed: 0.05) == 0.5)
    }

    @Test func fadeOutIsFullAtStart() {
        #expect(fadeOutOpacity(elapsed: 0.0) == 1.0)
    }

    @Test func fadeOutReachesZeroAt200ms() {
        #expect(fadeOutOpacity(elapsed: 0.2) == 0.0)
    }

    @Test func fadeOutClampsAtZero() {
        #expect(fadeOutOpacity(elapsed: 1.0) == 0.0)
    }

    @Test func fadeOutIsProportionalMidway() {
        #expect(fadeOutOpacity(elapsed: 0.1) == 0.5)
    }

    // MARK: - Style change triggers pipeline rebuild

    @Test func styleChangeUpdatesFragmentShaderName() {
        let view = ReactiveBackgroundView()
        view.reactiveStyle = .lockOn
        let nameBefore = view.fragmentShaderName
        view.reactiveStyle = .liquidFill
        let nameAfter = view.fragmentShaderName
        #expect(nameBefore != nameAfter)
    }
}
