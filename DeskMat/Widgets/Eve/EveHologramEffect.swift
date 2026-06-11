import SwiftUI

struct EveHologramEffect: WidgetShaderEffect {
    let intensity: Float
    let tint: Color

    var rate: WidgetShaderRate { .animation }
    var isEnabled: Bool { intensity > 0 }

    func shader(elapsed: TimeInterval, size: CGSize) -> ShaderApplication {
        let rgb = tint.resolvedRGB
        return .layer(
            ShaderLibrary.eveHologram(
                .float(Float(elapsed)),
                .float(intensity),
                .float(Float(size.width)),
                .float(Float(size.height)),
                .float(rgb.r), .float(rgb.g), .float(rgb.b)
            ),
            maxSampleOffset: CGSize(width: 24, height: 0)
        )
    }
}
