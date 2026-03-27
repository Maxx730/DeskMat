import SwiftUI

struct WeatherWidget: View {
    @State private var weatherService = WeatherService()
    @AppStorage("showLabels") private var showLabels = true

    var body: some View {
        VStack(spacing: 10) {
            DockWidget(
                cells: 2,
                isLoading: weatherService.isLoading,
                onRefresh: { await weatherService.fetch() }
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
            .task { await weatherService.fetch() }
            .onTapGesture {
                NSWorkspace.shared.open(URL(string: "weather://")!)
            }
            if showLabels {
                Text("Weather")
                    .font(.caption2)
                    .lineLimit(1)
                    .frame(width: DockWidget<EmptyView>.cellSize * 2)
                    .truncationMode(.tail)
            }
        }
    }
}
