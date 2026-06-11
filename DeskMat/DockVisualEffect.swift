import SwiftUI

struct DockVisualEffect: WidgetShaderEffect {
    let effect:    VisualEffect
    let intensity: Double

    var isEnabled: Bool { effect != .none }

    var rate: WidgetShaderRate {
        switch effect {
        case .scanlineWiggle, .heatShimmer: return .animation
        case .filmGrain, .oldFilm:          return .fps(24)
        case .hueDrift:                     return .fps(10)
        case .pixelate, .softBloom, .none:  return .fps(2)
        }
    }

    func shader(elapsed: TimeInterval, size: CGSize) -> ShaderApplication {
        let t = intensity
        switch effect {
        case .none:
            return .layer(ShaderLibrary.scanlineWiggle(
                .float(0), .float(0), .float(0), .float(0), .float(0)
            ), maxSampleOffset: CGSize(width: 50, height: 0))
        case .scanlineWiggle:
            return .layer(ShaderLibrary.scanlineWiggle(
                .float(Float(elapsed)),
                .float(Float(0.08 * t)),
                .float(Float(2.0 * t)),
                .float(Float(0.1 * t)),
                .float(Float(size.width))
            ), maxSampleOffset: CGSize(width: 50, height: 0))
        case .hueDrift:
            return .color(ShaderLibrary.hueDrift(
                .float(Float(elapsed)),
                .float(Float(0.05 + t * 0.15))
            ))
        case .filmGrain:
            return .color(ShaderLibrary.filmGrain(
                .float(Float(elapsed)),
                .float(Float(0.02 + t * 0.10))
            ))
        case .pixelate:
            return .layer(ShaderLibrary.pixelate(
                .float(Float(2.0 + t * 6.0))
            ), maxSampleOffset: CGSize(width: 8, height: 8))
        case .softBloom:
            // maxSampleOffset must cover the blur radius (3 px) in both axes so
            // edge pixels can sample neighbours without being clamped to the border.
            return .layer(ShaderLibrary.softBloom(
                .float(Float(t))
            ), maxSampleOffset: CGSize(width: 3, height: 3))
        case .heatShimmer:
            // maxSampleOffset height covers the maximum vertical displacement (3 px).
            return .layer(ShaderLibrary.heatShimmer(
                .float(Float(elapsed)),
                .float(Float(t))
            ), maxSampleOffset: CGSize(width: 0, height: 4))
        case .oldFilm:
            // Gate weave displaces up to ~1 px horizontally; no vertical sampling outside bounds.
            return .layer(ShaderLibrary.oldFilm(
                .float(Float(elapsed)),
                .float(Float(t)),
                .float(Float(size.width)),
                .float(Float(size.height))
            ), maxSampleOffset: CGSize(width: 1, height: 0))
        }
    }
}
