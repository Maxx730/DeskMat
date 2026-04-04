import SwiftUI

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
                content
                    .onGeometryChange(for: CGSize.self) { proxy in
                        proxy.size
                    } action: { newSize in
                        viewSize = newSize
                    }
                    .layerEffect(
                        shaderFor(visualEffect, elapsed: elapsed, intensity: t),
                        maxSampleOffset: CGSize(width: 50, height: 0)
                    )
            }
        } else {
            content
        }
    }

    private func shaderFor(_ effect: VisualEffect, elapsed: TimeInterval, intensity: Double) -> Shader {
        switch effect {
        case .none:
            // Won't be reached, but required for exhaustive switch
            return ShaderLibrary.scanlineWiggle(
                .float(0), .float(0), .float(0), .float(0), .float(0)
            )
        case .scanlineWiggle:
            return ShaderLibrary.scanlineWiggle(
                .float(Float(elapsed)),
                .float(Float(0.08 * intensity)),
                .float(Float(2.0 * intensity)),
                .float(Float(0.1 * intensity)),
                .float(Float(viewSize.width))
            )
        }
    }
}

extension View {
    func dockItemShader() -> some View {
        modifier(DockItemShader())
    }
}
