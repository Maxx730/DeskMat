import SwiftUI

/// Drops a reactive Metal shader into any widget ZStack.
/// Pass the desired style at the call site — no settings involvement.
struct WidgetShaderBackground: View {
    let style: ReactiveStyle
    var cornerRadius: CGFloat = 10

    var body: some View {
        ReactiveBackgroundRepresentable(style: style,
                                        cornerRadius: cornerRadius,
                                        limitFPS: true)
    }
}
