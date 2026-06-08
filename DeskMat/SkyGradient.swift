import SwiftUI

struct SkyGradient {

    private struct Stop {
        let hour: Double
        let r, g, b: Double
    }

    private static let stops: [Stop] = [
        Stop(hour:  0.0, r: 0.02, g: 0.05, b: 0.18), // midnight
        Stop(hour:  4.0, r: 0.04, g: 0.07, b: 0.22), // pre-dawn
        Stop(hour:  5.5, r: 0.15, g: 0.12, b: 0.40), // first light
        Stop(hour:  6.5, r: 0.80, g: 0.38, b: 0.12), // sunrise
        Stop(hour:  7.5, r: 0.92, g: 0.72, b: 0.35), // golden hour end
        Stop(hour:  9.0, r: 0.30, g: 0.62, b: 0.90), // morning
        Stop(hour: 12.0, r: 0.20, g: 0.52, b: 0.95), // noon
        Stop(hour: 15.0, r: 0.18, g: 0.48, b: 0.88), // afternoon
        Stop(hour: 17.5, r: 0.88, g: 0.55, b: 0.20), // pre-sunset
        Stop(hour: 18.5, r: 0.80, g: 0.28, b: 0.15), // sunset
        Stop(hour: 19.5, r: 0.18, g: 0.10, b: 0.38), // dusk
        Stop(hour: 21.0, r: 0.02, g: 0.05, b: 0.18), // night (matches midnight)
    ]

    static func color(for date: Date, weatherCode: Int) -> Color {
        let sky = color(for: date)
        guard let tint = conditionTint(for: weatherCode) else { return sky }
        // Resolve sky to RGB, then blend toward the tint color.
        let skyResolved = UIColorComponents(sky)
        return Color(
            red:   skyResolved.r * (1 - tint.amount) + tint.r * tint.amount,
            green: skyResolved.g * (1 - tint.amount) + tint.g * tint.amount,
            blue:  skyResolved.b * (1 - tint.amount) + tint.b * tint.amount
        )
    }

    private struct Tint { let r, g, b, amount: Double }

    private static func conditionTint(for code: Int) -> Tint? {
        switch code {
        case 0:           return nil                                      // clear
        case 1, 2:        return Tint(r: 0.55, g: 0.60, b: 0.65, amount: 0.10) // partly cloudy
        case 3:           return Tint(r: 0.50, g: 0.53, b: 0.57, amount: 0.25) // overcast
        case 45, 48:      return Tint(r: 0.65, g: 0.62, b: 0.58, amount: 0.30) // fog
        case 51...82:     return Tint(r: 0.35, g: 0.42, b: 0.55, amount: 0.35) // rain/drizzle
        case 71...86:     return Tint(r: 0.80, g: 0.85, b: 0.92, amount: 0.20) // snow
        case 95, 96, 99:  return Tint(r: 0.20, g: 0.20, b: 0.22, amount: 0.20) // thunder
        default:          return nil
        }
    }

    /// 0.0 = full day, 1.0 = full night. Derived from the sky luminosity so it
    /// tracks automatically as the gradient transitions through dawn and dusk.
    static func nightFactor(for date: Date, weatherCode: Int) -> Double {
        let c = UIColorComponents(color(for: date, weatherCode: weatherCode))
        let luminosity = 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
        return max(0, min(1, (0.20 - luminosity) / 0.15))
    }

    /// Returns the sky color blended 5% toward white, for use as a border.
    static func borderColor(for date: Date, weatherCode: Int) -> Color {
        let c = UIColorComponents(color(for: date, weatherCode: weatherCode))
        let cPerc = 0.10
        return Color(
            red:   c.r + (1 - c.r) * cPerc,
            green: c.g + (1 - c.g) * cPerc,
            blue:  c.b + (1 - c.b) * cPerc
        )
    }

    // Extracts linear RGB components from a SwiftUI Color via CGColor.
    private static func UIColorComponents(_ color: Color) -> (r: Double, g: Double, b: Double) {
        #if canImport(AppKit)
        let ns = NSColor(color).usingColorSpace(.deviceRGB) ?? .black
        return (ns.redComponent, ns.greenComponent, ns.blueComponent)
        #else
        let ui = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: nil)
        return (r, g, b)
        #endif
    }

    static func color(for date: Date) -> Color {
        let comps = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
        let hour = Double(comps.hour ?? 0)
               + Double(comps.minute ?? 0) / 60
               + Double(comps.second ?? 0) / 3600

        // Past the last stop — hold at final color
        guard let upper = stops.firstIndex(where: { $0.hour > hour }) else {
            let s = stops.last!
            return Color(red: s.r, green: s.g, blue: s.b)
        }

        let lo = stops[upper - 1]
        let hi = stops[upper]
        let t  = (hour - lo.hour) / (hi.hour - lo.hour)

        return Color(
            red:   lo.r + t * (hi.r - lo.r),
            green: lo.g + t * (hi.g - lo.g),
            blue:  lo.b + t * (hi.b - lo.b)
        )
    }
}
