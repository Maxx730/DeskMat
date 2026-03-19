import SwiftUI

struct WeatherWidget: View {
    @State private var weatherService = WeatherService()

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(red: 0.0, green: 0.0, blue: 0.0, opacity: 0.3))
                .stroke(Color(red: 0.0, green: 0.0, blue: 0.0, opacity: 0.5), lineWidth: 2)
            RoundedRectangle(cornerRadius: 10)
                .inset(by: 1)
                .fill(Color(red: 1.0, green: 1.0, blue: 1.0, opacity: 0.1))
                .stroke(Color(red: 1.0, green: 1.0, blue: 1.0, opacity: 0.1), lineWidth: 2)
            if weatherService.isLoading {
                ProgressView()
                    .scaleEffect(0.7)
                    .tint(.white)
            } else {
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
        }
        .frame(width: 128, height: 64)
        .overlay(alignment: .topTrailing) {
            Button {
                Task { await weatherService.fetch() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 8))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .buttonStyle(.plain)
            .padding(6)
        }
        .task { await weatherService.fetch() }
    }
}
