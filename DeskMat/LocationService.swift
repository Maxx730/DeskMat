import Foundation

struct LocationResult {
    let latitude: Double
    let longitude: Double
    let displayName: String
}

enum LocationService {

    private struct GeocodingResponse: Codable {
        struct Place: Codable {
            let name: String
            let latitude: Double
            let longitude: Double
            let country: String?
            let admin1: String?
        }
        let results: [Place]?
    }

    static func geocode(_ cityName: String) async throws -> LocationResult {
        let encoded = cityName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? cityName
        let urlString = "https://geocoding-api.open-meteo.com/v1/search?name=\(encoded)&count=1&language=en&format=json"
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }

        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(GeocodingResponse.self, from: data)

        guard let place = response.results?.first else { throw URLError(.cannotFindHost) }

        var display = place.name
        if let state = place.admin1 { display += ", \(state)" }

        return LocationResult(latitude: place.latitude, longitude: place.longitude, displayName: display)
    }
}
