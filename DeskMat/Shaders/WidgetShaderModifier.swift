import SwiftUI

// MARK: - Shared Shader Plumbing

enum ShaderApplication {
    case layer(Shader, maxSampleOffset: CGSize)
    case color(Shader)
}

extension View {
    @ViewBuilder
    func applyShader(_ application: ShaderApplication) -> some View {
        switch application {
        case .layer(let shader, let maxSampleOffset):
            self.layerEffect(shader, maxSampleOffset: maxSampleOffset)
        case .color(let shader):
            self.colorEffect(shader)
        }
    }

    func widgetShader<E: WidgetShaderEffect>(_ effect: E) -> some View {
        modifier(WidgetShaderModifier(effect: effect))
    }
}

// MARK: - WidgetShaderEffect Protocol

enum WidgetShaderRate {
    case animation
    case fps(Double)
}

protocol WidgetShaderEffect {
    var rate: WidgetShaderRate { get }
    var isEnabled: Bool { get }
    func shader(elapsed: TimeInterval, size: CGSize) -> ShaderApplication
}

extension WidgetShaderEffect {
    var isEnabled: Bool { true }
}

// MARK: - WidgetShaderModifier

struct WidgetShaderModifier<Effect: WidgetShaderEffect>: ViewModifier {
    let effect: Effect
    @State private var viewSize: CGSize = .zero
    private let startDate = Date.now

    func body(content: Content) -> some View {
        if effect.isEnabled {
            rateView(content: content)
        } else {
            content
        }
    }

    @ViewBuilder
    private func rateView(content: Content) -> some View {
        switch effect.rate {
        case .animation:
            TimelineView(.animation) { ctx in
                tickedView(content: content, date: ctx.date)
            }
        case .fps(let rate):
            TimelineView(.periodic(from: .now, by: 1.0 / rate)) { ctx in
                tickedView(content: content, date: ctx.date)
            }
        }
    }

    private func tickedView(content: Content, date: Date) -> some View {
        content
            .onGeometryChange(for: CGSize.self) { $0.size } action: { viewSize = $0 }
            .applyShader(effect.shader(elapsed: date.timeIntervalSince(startDate), size: viewSize))
    }
}

