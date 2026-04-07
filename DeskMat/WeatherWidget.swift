import SwiftUI

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
            DockWidget(
                cells: 2,
                isLoading: weatherService.isLoading,
                onRefresh: { await weatherService.fetch(latitude: weatherLatitude, longitude: weatherLongitude, locationName: weatherLocationName) }
            ) {
                VStack(spacing: 6) {
                    HStack {
                        Image(systemName: weatherService.iconName)
                            .font(.system(size: 20))
                            .foregroundStyle(.white)
                        Text(weatherService.temperature)
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    Text(weatherService.locationName)
                        .font(.system(size: 8))
                        .foregroundStyle(.white.opacity(0.8))
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(.white.opacity(0.15), in: Capsule())
                }
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
