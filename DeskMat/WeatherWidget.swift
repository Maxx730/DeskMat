import SwiftUI

struct WeatherWidget: View {
    @State private var weatherService = WeatherService()

    var body: some View {
        DockWidget(
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
    }
}
