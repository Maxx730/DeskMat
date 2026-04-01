import Foundation

// MARK: - Open-Meteo API Response

private struct WeatherResponse: Codable {
    let current: CurrentWeather

    struct CurrentWeather: Codable {
        let temperature2m: Double
        let weatherCode: Int

        enum CodingKeys: String, CodingKey {
            case temperature2m = "temperature_2m"
            case weatherCode = "weather_code"
        }
    }
}

// MARK: - WMO Weather Code → SF Symbol

private func weatherIcon(for code: Int) -> String {
    switch code {
    case 0:
        return "sun.max.fill"
    case 1, 2:
        return "cloud.sun.fill"
    case 3:
        return "cloud.fill"
    case 45, 48:
        return "cloud.fog.fill"
    case 51, 53, 55:
        return "cloud.drizzle.fill"
    case 56, 57:
        return "cloud.sleet.fill"
    case 61, 63, 65:
        return "cloud.rain.fill"
    case 66, 67:
        return "cloud.sleet.fill"
    case 71, 73, 75:
        return "cloud.snow.fill"
    case 77:
        return "snowflake"
    case 80, 81, 82:
        return "cloud.heavyrain.fill"
    case 85, 86:
        return "cloud.snow.fill"
    case 95:
        return "cloud.bolt.fill"
    case 96, 99:
        return "cloud.bolt.rain.fill"
    default:
        return "questionmark.circle"
    }
}

// MARK: - Weather Service

@Observable
class WeatherService {
    var temperature: String = Strings.Weather.temperaturePlaceholder
    var locationName: String = Strings.Weather.defaultLocationName
    var iconName: String = "cloud.sun.fill"
    var isLoading: Bool = false

    func fetch(latitude: Double, longitude: Double, locationName: String) async {
        await MainActor.run {
            self.locationName = locationName
            isLoading = true
        }

        guard let url = URL(string: "https://api.open-meteo.com/v1/forecast?latitude=\(latitude)&longitude=\(longitude)&current=temperature_2m,weather_code&temperature_unit=fahrenheit") else { return }

        // Ensure the loading indicator is visible for at least 0.5s
        async let minimumDelay: Void = Task.sleep(for: .milliseconds(500))

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(WeatherResponse.self, from: data)
            let temp = Int(response.current.temperature2m.rounded())

            _ = try? await minimumDelay

            await MainActor.run {
                temperature = "\(temp)°"
                iconName = weatherIcon(for: response.current.weatherCode)
                isLoading = false
            }
        } catch {
            print("Weather fetch failed: \(error)")
            _ = try? await minimumDelay
            await MainActor.run { isLoading = false }
        }
    }
}
