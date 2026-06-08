import SwiftUI

private struct StarsView: View {
    let opacity: Double

    // Deterministic star field — fixed positions and sizes, seeded once at launch.
    private static let positions: [(x: Double, y: Double, r: Double)] = {
        var seed: UInt64 = 0xABCD1234DEADBEEF
        func rand() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double(seed >> 33) / Double(1 << 31)
        }
        return (0..<28).map { _ in (rand(), rand(), 0.3 + rand() * 0.4) }
    }()

    var body: some View {
        Canvas { context, size in
            for star in Self.positions {
                let x = star.x * size.width
                let y = star.y * size.height
                let r = CGFloat(star.r)
                var dot = Path()
                dot.addEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
                // Larger stars are brighter; all scale with the night factor.
                let brightness = 0.55 + star.r * 0.45
                context.fill(dot, with: .color(.white.opacity(opacity * brightness)))
            }
        }
        .allowsHitTesting(false)
    }
}

struct WeatherWidget: View {
    static let cellCount = 2
    private let refreshInterval: TimeInterval = 15 * 60
    @State private var weatherService = WeatherService()
    @AppStorage("showLabels")           private var showLabels = true
    @AppStorage("weatherLatitude")      private var weatherLatitude     = 37.2707
    @AppStorage("weatherLongitude")     private var weatherLongitude    = -76.7075
    @AppStorage("weatherLocationName")  private var weatherLocationName = Strings.Weather.defaultLocationName

    var body: some View {
        VStack(spacing: 10) {
            TimelineView(.everyMinute) { timeline in
                DockWidget(
                    cells: 2,
                    isLoading: weatherService.isLoading,
                    backgroundColor: SkyGradient.color(for: timeline.date, weatherCode: weatherService.weatherCode),
                    onRefresh: { await weatherService.fetch(latitude: weatherLatitude, longitude: weatherLongitude, locationName: weatherLocationName) }
                ) {
                    ZStack {
                        StarsView(opacity: SkyGradient.nightFactor(
                            for: timeline.date, weatherCode: weatherService.weatherCode))
                        CelestialDialView(date: timeline.date)
                        VStack(spacing: 6) {
                            HStack {
                                Text(weatherService.temperature)
                                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.white).offset(y: 6)
                            }
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .task(id: weatherLatitude) {
                while !Task.isCancelled {
                    await weatherService.fetch(latitude: weatherLatitude, longitude: weatherLongitude, locationName: weatherLocationName)
                    try? await Task.sleep(for: .seconds(refreshInterval))
                }
            }
            .onTapGesture {
                NSWorkspace.shared.open(URL(string: "weather://")!)
            }
            if showLabels {
                Text(Strings.Widgets.weather)
                    .font(.caption2)
                    .lineLimit(1)
                    .frame(width: DockWidget<EmptyView>.width(for: Self.cellCount))
                    .truncationMode(.tail)
            }
        }
    }
}
