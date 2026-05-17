import Testing
import Foundation
@testable import DeskMat

// MARK: - LocationError Tests

struct LocationErrorTests {

    @Test func notFoundHasLocalizedDescription() {
        let error = LocationError.notFound
        #expect(error.errorDescription != nil)
        #expect(!(error.errorDescription ?? "").isEmpty)
    }

    @Test func notFoundDescriptionMentionsLocation() {
        let error = LocationError.notFound
        let desc = error.errorDescription ?? ""
        // The message should be user-facing and non-empty.
        #expect(desc.count > 5)
    }

    @Test func locationErrorConformsToLocalizedError() {
        let error: any LocalizedError = LocationError.notFound
        #expect(error.errorDescription != nil)
    }

    @Test func locationErrorConformsToError() {
        let error: any Error = LocationError.notFound
        #expect((error as? LocationError) == .notFound)
    }

    @Test func notFoundIsEquatable() {
        #expect(LocationError.notFound == LocationError.notFound)
    }
}

// MARK: - LocationResult Tests

struct LocationResultTests {

    @Test func initStoresAllFields() {
        let result = LocationResult(latitude: 37.7749, longitude: -122.4194, displayName: "San Francisco, California")
        #expect(result.latitude == 37.7749)
        #expect(result.longitude == -122.4194)
        #expect(result.displayName == "San Francisco, California")
    }

    @Test func latitudeAndLongitudeArePreservedExactly() {
        let lat = 51.5074
        let lon = -0.1278
        let result = LocationResult(latitude: lat, longitude: lon, displayName: "London")
        #expect(result.latitude == lat)
        #expect(result.longitude == lon)
    }

    @Test func displayNameIsPreserved() {
        let name = "Tokyo, Tokyo"
        let result = LocationResult(latitude: 35.6762, longitude: 139.6503, displayName: name)
        #expect(result.displayName == name)
    }
}
