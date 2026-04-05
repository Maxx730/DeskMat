import SwiftUI

private enum ShaderApplication {
    case layer(Shader)
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
            let t = intensity
            TimelineView(.animation) { context in
                let elapsed = context.date.timeIntervalSince(startDate)
                let application = shaderFor(visualEffect, elapsed: elapsed, intensity: t)
                content
                    .onGeometryChange(for: CGSize.self) { proxy in
                        proxy.size
                    } action: { newSize in
                        viewSize = newSize
                    }
                    .applyShader(application)
            }
        } else {
            content
        }
    }

    private func shaderFor(_ effect: VisualEffect, elapsed: TimeInterval, intensity: Double) -> ShaderApplication {
        switch effect {
        case .none:
            return .layer(ShaderLibrary.scanlineWiggle(
                .float(0), .float(0), .float(0), .float(0), .float(0)
            ))
        case .scanlineWiggle:
            return .layer(ShaderLibrary.scanlineWiggle(
                .float(Float(elapsed)),
                .float(Float(0.08 * intensity)),
                .float(Float(2.0 * intensity)),
                .float(Float(0.1 * intensity)),
                .float(Float(viewSize.width))
            ))
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
            ))
        case .softBloom:
            return .layer(ShaderLibrary.softBloom(
                .float(Float(intensity))
            ))
        }
    }
}

private extension View {
    @ViewBuilder
    func applyShader(_ application: ShaderApplication) -> some View {
        switch application {
        case .layer(let shader):
            self.layerEffect(shader, maxSampleOffset: CGSize(width: 50, height: 0))
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
