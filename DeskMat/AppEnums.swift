import Foundation

enum DockPosition: String, CaseIterable {
    case bottom = "Bottom"
    case top = "Top"
}

enum AppearanceMode: String, CaseIterable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"
}

enum VisualEffect: String, CaseIterable {
    case none = "None"
    case scanlineWiggle = "Scanline Wiggle"
    case hueDrift = "Hue Drift"
    case filmGrain = "Film Grain"
    case pixelate = "Pixelate"
    case softBloom = "Soft Bloom"
}

enum DockBackground: String, CaseIterable {
    case system = "System"
    case color = "Color"
    case transparent = "Transparent"
}

enum HideAnimation: String, CaseIterable {
    case fade  = "Fade"
    case slide = "Slide"
}

enum SystemMetric: String, CaseIterable {
    case cpu     = "CPU"
    case ram     = "RAM"
    case network = "Network"
}
