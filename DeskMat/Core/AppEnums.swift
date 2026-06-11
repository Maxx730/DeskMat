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
    case heatShimmer = "Heat Shimmer"
    case oldFilm = "Old Film"
}

enum DockBackground: String, CaseIterable {
    case system = "System"
    case color = "Color"
    case transparent = "Transparent"
    case reactive = "Reactive"
}

enum ReactiveStyle: String, CaseIterable {
    case none      = "None"
    case electro   = "Electro"
    case starfield = "Starfield"
    case colors     = "Colors"
    case topograph  = "Topograph"
    case snow       = "Snow"
    case cellular   = "Cellular"
}

enum HideAnimation: String, CaseIterable {
    case fade  = "Fade"
    case slide = "Slide"
}

enum HoverSize: String, CaseIterable {
    case small  = "Small"
    case medium = "Medium"
    case large  = "Large"

    var scale: Double {
        switch self {
        case .small:  1.2
        case .medium: 1.5
        case .large:  1.8
        }
    }
}

enum HoverAnimation: String, CaseIterable {
    case bounce = "Bounce"
    case pulse  = "Pulse"
    case jiggle = "Jiggle"
    case pop    = "Pop"
    case shine  = "Shine"
    case none   = "None"
}

enum SystemMetric: String, CaseIterable {
    case cpu     = "CPU"
    case ram     = "RAM"
    case network = "Network"

    var cellCount: Int {
        switch self {
        case .cpu:            return 1
        case .ram, .network:  return 2
        }
    }
}

enum ClockStyle: String, CaseIterable {
    case system = "System"
    case flat   = "Flat"
}
