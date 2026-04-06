import Testing
import Foundation
@testable import DeskMat

// MARK: - WeatherService Tests

struct WeatherServiceTests {

    @Test func initialStateHasPlaceholders() {
        let service = WeatherService()

        #expect(service.temperature == "--°")
        #expect(service.locationName == "Williamsburg, VA")
        #expect(service.iconName == "cloud.sun.fill")
        #expect(service.isLoading == false)
    }
}
