import Foundation

// Fetches and stores restaurant opening-hours schedules from Google Places API.
// First call per restaurant hits the API (Enterprise SKU, one-time cost).
// All subsequent calls compute isOpenNow locally from the stored schedule — no API charge.
actor PlacesService {
    static let shared = PlacesService()
    private init() {}

    private struct Period: Codable {
        let openDay: Int   // 0=Sun ... 6=Sat
        let openHour: Int
        let openMin: Int
        let closeDay: Int
        let closeHour: Int
        let closeMin: Int
    }

    private static func key(_ id: String) -> String { "sunzzari_hours_\(id)" }

    // MARK: - Public

    func isOpenNow(restaurant: Restaurant) async -> Bool? {
        if let stored = loadPeriods(for: restaurant.id) {
            return computeOpenNow(periods: stored)
        }
        if let periods = await fetchPeriods(for: restaurant) {
            storePeriods(periods, for: restaurant.id)
            return computeOpenNow(periods: periods)
        }
        return nil  // no data = show by default
    }

    // MARK: - Computation

    private func computeOpenNow(periods: [Period]) -> Bool {
        let cal = Calendar.current
        let now = Date()
        // Calendar.weekday is 1-indexed (1=Sun), convert to 0-indexed
        let day = cal.component(.weekday, from: now) - 1
        let hour = cal.component(.hour, from: now)
        let min = cal.component(.minute, from: now)
        let current = day * 1440 + hour * 60 + min

        return periods.contains { p in
            let open = p.openDay * 1440 + p.openHour * 60 + p.openMin
            let close = p.closeDay * 1440 + p.closeHour * 60 + p.closeMin
            if close >= open {
                return current >= open && current < close
            } else {
                // Sat→Sun week-boundary wrap (e.g. Sat 23:00 → Sun 02:00)
                return current >= open || current < close
            }
        }
    }

    // MARK: - Persistence

    private func loadPeriods(for id: String) -> [Period]? {
        guard let data = UserDefaults.standard.data(forKey: Self.key(id)),
              let periods = try? JSONDecoder().decode([Period].self, from: data),
              !periods.isEmpty else { return nil }
        return periods
    }

    private func storePeriods(_ periods: [Period], for id: String) {
        guard let data = try? JSONEncoder().encode(periods) else { return }
        UserDefaults.standard.set(data, forKey: Self.key(id))
    }

    // MARK: - Network

    private func fetchPeriods(for restaurant: Restaurant) async -> [Period]? {
        let apiKey = await MainActor.run { Secrets.GooglePlaces.apiKey }
        guard !apiKey.isEmpty else { return nil }

        let query = [restaurant.name, restaurant.neighborhood, restaurant.location]
            .filter { !$0.isEmpty }.joined(separator: ", ")

        var request = URLRequest(url: URL(string: "https://places.googleapis.com/v1/places:searchText")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-Goog-Api-Key")
        request.setValue("places.regularOpeningHours", forHTTPHeaderField: "X-Goog-FieldMask")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "textQuery": query,
            "maxResultCount": 1
        ])

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }

        struct APIResponse: Decodable {
            struct Place: Decodable {
                struct Hours: Decodable {
                    struct APIPeriod: Decodable {
                        struct Point: Decodable { let day: Int; let hour: Int; let minute: Int }
                        let open: Point
                        let close: Point?  // nil = 24-hour venue; those show by default (nil return)
                    }
                    let periods: [APIPeriod]?
                }
                let regularOpeningHours: Hours?
            }
            let places: [Place]?
        }

        guard let parsed = try? JSONDecoder().decode(APIResponse.self, from: data),
              let apiPeriods = parsed.places?.first?.regularOpeningHours?.periods,
              !apiPeriods.isEmpty else { return nil }

        return apiPeriods.compactMap { p in
            guard let close = p.close else { return nil }
            return Period(
                openDay: p.open.day, openHour: p.open.hour, openMin: p.open.minute,
                closeDay: close.day, closeHour: close.hour, closeMin: close.minute
            )
        }
    }
}
