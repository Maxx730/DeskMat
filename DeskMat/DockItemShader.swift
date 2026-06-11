import SwiftUI

/// Applies the selected visual effect shader to any dock item.
struct DockItemShader: ViewModifier {
    @Environment(LicenseManager.self) private var entitlements
    @AppStorage("visualEffect")            private var visualEffect: VisualEffect = .none
    @AppStorage("dockItemShaderIntensity") private var intensity = 0.5

    func body(content: Content) -> some View {
        content.widgetShader(DockVisualEffect(
            effect:    entitlements.isPro ? visualEffect : .none,
            intensity: intensity
        ))
    }
}

extension View {
    func dockItemShader() -> some View {
        modifier(DockItemShader())
    }
}
