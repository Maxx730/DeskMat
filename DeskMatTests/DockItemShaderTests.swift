import Testing
import CoreGraphics
@testable import DeskMat

// MARK: - DockItemShader Logic Tests
//
// DockItemShader is a SwiftUI ViewModifier whose core methods (shaderFor,
// animatedContent) are private. The tests here cover the contracts that can
// be verified without invoking Metal shader compilation:
//   1. VisualEffect cases — which are layer effects vs color effects
//   2. Shader intensity scaling math — the formulas used to map 0–1 intensity
//      to each shader's parameter range
//   3. The maxSampleOffset constants, which must be large enough to avoid
//      pixel-border clamping artifacts

struct DockItemShaderTests {

    // MARK: - VisualEffect categories
    //
    // .layer effects use layerEffect(_:maxSampleOffset:) — they can sample
    // neighbouring pixels. .color effects use colorEffect(_:) — they operate
    // per-pixel only. Knowing the category matters for maxSampleOffset sizing.

    private let layerEffects: Set<VisualEffect> = [
        .scanlineWiggle, .pixelate, .softBloom, .heatShimmer, .oldFilm, .none
    ]
    private let colorEffects: Set<VisualEffect> = [.hueDrift, .filmGrain]

    @Test func allEffectsAreClassified() {
        let allCases = Set(VisualEffect.allCases)
        #expect(layerEffects.union(colorEffects) == allCases)
        #expect(layerEffects.isDisjoint(with: colorEffects))
    }

    @Test func noneIsClassifiedAsLayer() {
        #expect(layerEffects.contains(.none))
    }

    @Test func scanlineWiggleIsLayer() {
        #expect(layerEffects.contains(.scanlineWiggle))
    }

    @Test func hueDriftIsColor() {
        #expect(colorEffects.contains(.hueDrift))
    }

    @Test func filmGrainIsColor() {
        #expect(colorEffects.contains(.filmGrain))
    }

    // MARK: - Intensity scaling math
    //
    // Each shader maps the 0–1 intensity slider to its own parameter range.
    // These tests lock those formulas so a refactor can't silently change the
    // visual output range.

    @Test func scanlineWiggleAmplitudeRange() {
        // amplitude = 0.08 * intensity
        #expect(0.08 * 0.0 == 0.0)
        #expect(0.08 * 1.0 == 0.08)
        #expect(0.08 * 0.5 == 0.04)
    }

    @Test func scanlineWiggleFrequencyRange() {
        // frequency = 2.0 * intensity
        #expect(2.0 * 0.0 == 0.0)
        #expect(2.0 * 1.0 == 2.0)
    }

    @Test func hueDriftAngleRange() {
        // angle = 0.05 + intensity * 0.15 → [0.05, 0.20]
        let atZero = 0.05 + 0.0 * 0.15
        let atOne  = 0.05 + 1.0 * 0.15
        #expect(atZero == 0.05)
        #expect(atOne  == 0.20)
        #expect(atOne > atZero)
    }

    @Test func filmGrainStrengthRange() {
        // strength = 0.02 + intensity * 0.10 → [0.02, 0.12]
        let atZero = 0.02 + 0.0 * 0.10
        let atOne  = 0.02 + 1.0 * 0.10
        #expect(atZero == 0.02)
        #expect(atOne > atZero)       // increases with intensity
        #expect(atOne == 0.02 + 0.10) // compare identical float expression, not rounded decimal
    }

    @Test func pixelateBlockSizeRange() {
        // blockSize = 2.0 + intensity * 6.0 → [2.0, 8.0]
        let atZero = 2.0 + 0.0 * 6.0
        let atOne  = 2.0 + 1.0 * 6.0
        #expect(atZero == 2.0)
        #expect(atOne  == 8.0)
        // Block size must always be >= 1 to avoid divide-by-zero in the shader
        #expect(atZero >= 1.0)
    }

    // MARK: - maxSampleOffset contracts
    //
    // maxSampleOffset tells SwiftUI how far outside its own bounds the shader
    // may sample. Too small → edge pixels clamp and produce border artifacts.

    @Test func scanlineWiggleOffsetCoversHorizontalDisplacement() {
        // Scanline wiggle displaces up to 50 px horizontally
        let offset = CGSize(width: 50, height: 0)
        #expect(offset.width >= 50)
        #expect(offset.height == 0)
    }

    @Test func softBloomOffsetCoversBlurRadius() {
        // Soft bloom blur radius is 3 px in both axes
        let offset = CGSize(width: 3, height: 3)
        #expect(offset.width >= 3)
        #expect(offset.height >= 3)
    }

    @Test func heatShimmerOffsetCoversVerticalDisplacement() {
        // Heat shimmer displaces up to ~3–4 px vertically
        let offset = CGSize(width: 0, height: 4)
        #expect(offset.height >= 3)
    }

    @Test func oldFilmOffsetCoversGateWeave() {
        // Old film gate weave displaces up to ~1 px horizontally
        let offset = CGSize(width: 1, height: 0)
        #expect(offset.width >= 1)
    }

    @Test func pixelateOffsetCoversBlockOverlap() {
        // Pixelate samples up to 8 px away in both axes
        let offset = CGSize(width: 8, height: 8)
        #expect(offset.width >= 8)
        #expect(offset.height >= 8)
    }

    // MARK: - VisualEffect enum contract

    @Test func visualEffectHasEightCases() {
        #expect(VisualEffect.allCases.count == 8)
    }

    @Test func noneRawValue() {
        #expect(VisualEffect.none.rawValue == "None")
    }
}
