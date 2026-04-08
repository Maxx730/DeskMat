import SwiftUI

private enum ShaderApplication {
    case layer(Shader, maxSampleOffset: CGSize)
    case color(Shader)
}

/// Applies the selected visual effect shader to any dock item.
struct DockItemShader: ViewModifier {
    @Environment(EntitlementManager.self) private var entitlements
    @AppStorage("visualEffect") private var visualEffect: VisualEffect = .none
    @AppStorage("dockItemShaderIntensity") private var intensity = 0.5
    @State private var viewSize: CGSize = CGSize(width: 64, height: 64)
    private let startDate = Date.now

    func body(content: Content) -> some View {
        if entitlements.isPro && visualEffect != .none {
            animatedContent(content: content)
        } else {
            content
        }
    }

    // Picks the lowest frame rate that still looks correct for each effect.
    // TimelineSchedule is a protocol — type erasure isn't available, so we
    // use a @ViewBuilder switch to select the right concrete TimelineView.
    @ViewBuilder
    private func animatedContent(content: Content) -> some View {
        let t = intensity
        switch visualEffect {
        case .none:
            content
        case .scanlineWiggle, .heatShimmer:
            // Motion-dependent — needs full display refresh rate
            TimelineView(.animation) { ctx in
                tickedView(content: content, date: ctx.date, intensity: t)
            }
        case .filmGrain, .oldFilm:
            // Grain/noise texture — 24 fps is imperceptible from 60 fps
            TimelineView(.periodic(from: .now, by: 1.0 / 24.0)) { ctx in
                tickedView(content: content, date: ctx.date, intensity: t)
            }
        case .hueDrift:
            // Slow color drift — 10 fps is plenty
            TimelineView(.periodic(from: .now, by: 1.0 / 10.0)) { ctx in
                tickedView(content: content, date: ctx.date, intensity: t)
            }
        case .pixelate, .softBloom:
            // Static effect — doesn't use elapsed time, 2 fps is invisible
            TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
                tickedView(content: content, date: ctx.date, intensity: t)
            }
        }
    }

    private func tickedView(content: Content, date: Date, intensity: Double) -> some View {
        let elapsed = date.timeIntervalSince(startDate)
        return content
            .onGeometryChange(for: CGSize.self) { $0.size } action: { viewSize = $0 }
            .applyShader(shaderFor(visualEffect, elapsed: elapsed, intensity: intensity))
    }

    private func shaderFor(_ effect: VisualEffect, elapsed: TimeInterval, intensity: Double) -> ShaderApplication {
        switch effect {
        case .none:
            return .layer(ShaderLibrary.scanlineWiggle(
                .float(0), .float(0), .float(0), .float(0), .float(0)
            ), maxSampleOffset: CGSize(width: 50, height: 0))
        case .scanlineWiggle:
            return .layer(ShaderLibrary.scanlineWiggle(
                .float(Float(elapsed)),
                .float(Float(0.08 * intensity)),
                .float(Float(2.0 * intensity)),
                .float(Float(0.1 * intensity)),
                .float(Float(viewSize.width))
            ), maxSampleOffset: CGSize(width: 50, height: 0))
        case .hueDrift:
            return .color(ShaderLibrary.hueDrift(
                .float(Float(elapsed)),
                .float(Float(0.05 + intensity * 0.15))
            ))
        case .filmGrain:
            return .color(ShaderLibrary.filmGrain(
                .float(Float(elapsed)),
                .float(Float(0.02 + intensity * 0.10))
            ))
        case .pixelate:
            return .layer(ShaderLibrary.pixelate(
                .float(Float(2.0 + intensity * 6.0))
            ), maxSampleOffset: CGSize(width: 8, height: 8))
        case .softBloom:
            // maxSampleOffset must cover the blur radius (3 px) in both axes so
            // edge pixels can sample neighbours without being clamped to the border.
            return .layer(ShaderLibrary.softBloom(
                .float(Float(intensity))
            ), maxSampleOffset: CGSize(width: 3, height: 3))
        case .heatShimmer:
            // maxSampleOffset height covers the maximum vertical displacement (3 px).
            return .layer(ShaderLibrary.heatShimmer(
                .float(Float(elapsed)),
                .float(Float(intensity))
            ), maxSampleOffset: CGSize(width: 0, height: 4))
        case .oldFilm:
            // Gate weave displaces up to ~1 px horizontally; no vertical sampling outside bounds.
            return .layer(ShaderLibrary.oldFilm(
                .float(Float(elapsed)),
                .float(Float(intensity)),
                .float(Float(viewSize.width)),
                .float(Float(viewSize.height))
            ), maxSampleOffset: CGSize(width: 1, height: 0))
        }
    }
}

private extension View {
    @ViewBuilder
    func applyShader(_ application: ShaderApplication) -> some View {
        switch application {
        case .layer(let shader, let maxSampleOffset):
            self.layerEffect(shader, maxSampleOffset: maxSampleOffset)
        case .color(let shader):
            self.colorEffect(shader)
        }
    }
}

extension View {
    func dockItemShader() -> some View {
        modifier(DockItemShader())
    }
}
