import Foundation
import CoreLocation

/// Shared geocoder for the Hub maps (Around Town, Restaurants).
///
/// These maps used MKLocalSearch, which cannot do this job. MapKit throttles
/// place search by volume: measured 2026-08-24 against 120 real restaurant names,
/// 5-way concurrency returned 33 hits and 70 `MKError.loadingThrottled`, and a
/// paced one-at-a-time retry immediately afterwards was throttled on all 120. The
/// failures were being discarded silently, which is why a 380-place map only ever
/// drew a few dozen pins.
///
/// The travel map never had this problem because it does not use MapKit -- it
/// calls the app's own Vercel endpoint (Google Geocoding with a server-side Redis
/// cache). The same 60 names resolve there in about 3 seconds, 60 for 60. So the
/// Hub maps now go through the same endpoint.
enum PlaceGeocoder {
    private static let endpoint = "https://elisa-travel-map.vercel.app/api/geocode"

    /// Resolves a place to a coordinate. `city` narrows the search the same way
    /// the travel map passes a leg's city. Returns nil when the endpoint has no
    /// match or is unreachable; callers cache the miss so it is not retried in a
    /// tight loop.
    static func coordinate(venue: String, city: String) async -> CLLocationCoordinate2D? {
        guard !venue.isEmpty || !city.isEmpty else { return nil }
        guard var components = URLComponents(string: endpoint) else { return nil }
        components.queryItems = [
            URLQueryItem(name: "venue", value: venue),
            URLQueryItem(name: "city", value: city)
        ]
        guard let url = components.url else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 12
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return nil
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let lat = json["lat"] as? Double,
                  let lng = json["lng"] as? Double else { return nil }
            return CLLocationCoordinate2D(latitude: lat, longitude: lng)
        } catch {
            return nil
        }
    }
}
