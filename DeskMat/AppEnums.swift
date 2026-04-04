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
}

enum DockBackground: String, CaseIterable {
    case system = "System"
    case color = "Color"
    case transparent = "Transparent"
}
