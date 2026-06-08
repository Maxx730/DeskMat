import SwiftUI

struct ImageProgressView: View {
    let image:         Image
    let value:         Double
    var axis:          Axis   = .horizontal
    var reversed:      Bool   = false
    var dimBrightness: Double = -0.35
    var dimSaturation: Double = 0.4

    var body: some View {
        ZStack {
            image
                .resizable()
                .scaledToFit()
                .brightness(dimBrightness)
                .saturation(dimSaturation)

            image
                .resizable()
                .scaledToFit()
                .clipShape(ProgressClipShape(value: value, axis: axis, reversed: reversed))
        }
    }
}

private struct ProgressClipShape: Shape, Animatable {
    var value:    Double
    var axis:     Axis
    var reversed: Bool

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let v = max(0, min(1, value))
        let r: CGRect
        switch (axis, reversed) {
        case (.horizontal, false):
            r = CGRect(x: rect.minX, y: rect.minY,
                       width: rect.width * v, height: rect.height)
        case (.horizontal, true):
            r = CGRect(x: rect.maxX - rect.width * v, y: rect.minY,
                       width: rect.width * v, height: rect.height)
        case (.vertical, false):
            r = CGRect(x: rect.minX, y: rect.maxY - rect.height * v,
                       width: rect.width, height: rect.height * v)
        case (.vertical, true):
            r = CGRect(x: rect.minX, y: rect.minY,
                       width: rect.width, height: rect.height * v)
        }
        return Path(r)
    }
}
