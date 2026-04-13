import Foundation
import MapKit

final class TravelService: @unchecked Sendable {
    static let shared = TravelService()
    private let baseURL = "https://api.notion.com/v1"

    // Bump this when geocoding logic changes to clear stale caches
    private static let geocodeVersion = 2
    private static let geocodeVersionKey = "sunzzari_travel_geocode_version"

    private init() {
        let stored = UserDefaults.standard.integer(forKey: Self.geocodeVersionKey)
        if stored < Self.geocodeVersion {
            let defaults = UserDefaults.standard
            for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("sunzzari_travel_geo_") {
                defaults.removeObject(forKey: key)
            }
            defaults.set(Self.geocodeVersion, forKey: Self.geocodeVersionKey)
        }
    }

    // MARK: - Memory cache

    private var tripsCache: (trips: [Trip], at: Date)?
    private var itemsCache: [String: (items: [TripItem], at: Date)] = [:]
    private let cacheTTL: TimeInterval = 300 // 5 minutes

    var isOffline = false

    func invalidateTrips() { tripsCache = nil }
    func invalidateItems(tripId: String) { itemsCache[tripId] = nil }

    // MARK: - Disk cache

    private var diskCacheDir: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    }

    private func saveToDisk(_ data: Data, name: String) {
        let url = diskCacheDir.appendingPathComponent("sunzzari_travel_\(name).json")
        try? data.write(to: url, options: .atomic)
    }

    private func loadFromDisk(name: String) -> Data? {
        let url = diskCacheDir.appendingPathComponent("sunzzari_travel_\(name).json")
        return try? Data(contentsOf: url)
    }

    // MARK: - Disk cache accessors

    func tripsDiskCache() -> [Trip]? {
        loadFromDisk(name: "trips").map { parseTrips(from: $0) }
    }

    func itemsDiskCache(tripId: String) -> [TripItem]? {
        let normalized = tripId.replacingOccurrences(of: "-", with: "")
        return loadFromDisk(name: "items_\(normalized)").map { parseItems(from: $0, tripId: tripId) }
    }

    // MARK: - Headers

    private var headers: [String: String] {
        [
            "Authorization":   "Bearer \(Constants.Notion.token)",
            "Notion-Version":  Constants.Notion.version,
            "Content-Type":    "application/json"
        ]
    }

    // MARK: - Fetch Trips

    func fetchTrips(force: Bool = false) async throws -> [Trip] {
        if !force, let cached = tripsCache, Date().timeIntervalSince(cached.at) < cacheTTL {
            isOffline = false
            return cached.trips
        }
        do {
            let data = try await queryDatabase(
                id: Constants.Travel.tripsDBID,
                sorts: [["property": "Departure Date", "direction": "descending"]]
            )
            let trips = parseTrips(from: data)
            tripsCache = (trips, Date())
            saveToDisk(data, name: "trips")
            isOffline = false
            return trips
        } catch {
            if let diskData = loadFromDisk(name: "trips") {
                let trips = parseTrips(from: diskData)
                tripsCache = (trips, Date())
                isOffline = true
                return trips
            }
            throw error
        }
    }

    // MARK: - Fetch Trip Items

    func fetchTripItems(tripId: String, force: Bool = false) async throws -> [TripItem] {
        let normalized = tripId.replacingOccurrences(of: "-", with: "")
        if !force, let cached = itemsCache[tripId], Date().timeIntervalSince(cached.at) < cacheTTL {
            isOffline = false
            return cached.items
        }
        do {
            let filter: [String: Any] = [
                "property": "Trip",
                "relation": ["contains": tripId]
            ]
            let data = try await queryDatabase(
                id: Constants.Travel.itemsDBID,
                sorts: [["property": "Name", "direction": "ascending"]],
                filter: filter
            )
            let items = parseItems(from: data, tripId: tripId)
            itemsCache[tripId] = (items, Date())
            saveToDisk(data, name: "items_\(normalized)")
            isOffline = false
            return items
        } catch {
            if let diskData = loadFromDisk(name: "items_\(normalized)") {
                let items = parseItems(from: diskData, tripId: tripId)
                itemsCache[tripId] = (items, Date())
                isOffline = true
                return items
            }
            throw error
        }
    }

    // MARK: - Cached Coordinates (synchronous, no network)

    func applyCachedCoordinates(_ items: [TripItem]) -> [TripItem] {
        var result = items
        for i in result.indices where !result[i].hasCoordinates && !result[i].venue.isEmpty {
            let key = TripItem.geoKey(for: result[i].id)
            if let cached = UserDefaults.standard.string(forKey: key) {
                let parts = cached.split(separator: ",")
                if parts.count == 2, let lat = Double(parts[0]), let lon = Double(parts[1]) {
                    result[i].latitude = lat
                    result[i].longitude = lon
                }
            }
        }
        return result
    }

    // MARK: - Geocoding

    func geocodeItems(_ items: [TripItem]) async -> [TripItem] {
        var result = items
        let toGeocode = items.enumerated().filter { !$0.element.hasCoordinates && !$0.element.venue.isEmpty }

        // First pass: apply UserDefaults cache hits (no concurrency needed)
        var needsNetwork: [(index: Int, item: TripItem)] = []
        for (index, item) in toGeocode {
            let key = TripItem.geoKey(for: item.id)
            if let cached = UserDefaults.standard.string(forKey: key) {
                let parts = cached.split(separator: ",")
                if parts.count == 2, let lat = Double(parts[0]), let lon = Double(parts[1]) {
                    result[index].latitude = lat
                    result[index].longitude = lon
                    continue
                }
            }
            needsNetwork.append((index, item))
        }

        // Pre-resolve unique cities to regions for search bias
        var cityRegions: [String: MKCoordinateRegion] = [:]
        let uniqueCities = Set(needsNetwork.map(\.item.legCity).filter { !$0.isEmpty })
        for city in uniqueCities {
            let cityReq = MKLocalSearch.Request()
            cityReq.naturalLanguageQuery = city
            if let resp = try? await MKLocalSearch(request: cityReq).start(),
               let first = resp.mapItems.first {
                cityRegions[city] = MKCoordinateRegion(
                    center: first.placemark.coordinate,
                    latitudinalMeters: 50_000, longitudinalMeters: 50_000
                )
            }
        }

        // Second pass: geocode uncached items via network
        await withTaskGroup(of: (Int, Double, Double)?.self) { group in
            for (index, item) in needsNetwork {
                let region = cityRegions[item.legCity]
                group.addTask {
                    let query = [item.venue, item.legCity]
                        .filter { !$0.isEmpty }
                        .joined(separator: ", ")
                    let request = MKLocalSearch.Request()
                    request.naturalLanguageQuery = query
                    if let region { request.region = region }
                    do {
                        let response = try await MKLocalSearch(request: request).start()
                        if let first = response.mapItems.first {
                            let lat = first.placemark.coordinate.latitude
                            let lon = first.placemark.coordinate.longitude
                            return (index, lat, lon)
                        }
                    } catch {
                        print("[TravelService] geocode failed for '\(query)': \(error.localizedDescription)")
                    }
                    return nil
                }
            }

            for await result_ in group {
                if let (index, lat, lon) = result_ {
                    result[index].latitude = lat
                    result[index].longitude = lon
                    let key = TripItem.geoKey(for: result[index].id)
                    UserDefaults.standard.set("\(lat),\(lon)", forKey: key)
                }
            }
        }

        return result
    }

    // MARK: - Notion API

    private func queryDatabase(id: String, sorts: [[String: Any]], filter: [String: Any]? = nil) async throws -> Data {
        var allResults: [[String: Any]] = []
        var startCursor: String? = nil

        repeat {
            var body: [String: Any] = ["sorts": sorts, "page_size": 100]
            if let filter { body["filter"] = filter }
            if let cursor = startCursor { body["start_cursor"] = cursor }

            let url = URL(string: "\(baseURL)/databases/\(id)/query")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let results = json["results"] as? [[String: Any]] else { break }
            allResults.append(contentsOf: results)

            let hasMore = json["has_more"] as? Bool ?? false
            startCursor = hasMore ? json["next_cursor"] as? String : nil
        } while startCursor != nil

        return try JSONSerialization.data(withJSONObject: ["results": allResults])
    }

    // MARK: - Parsers

    private func parseTrips(from data: Data) -> [Trip] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else { return [] }
        return results.compactMap { page in
            guard let id = page["id"] as? String,
                  let props = page["properties"] as? [String: Any] else { return nil }
            let statusStr = extractSelect(from: props["Trip Status"])

            // Cover image: custom property first, then page cover
            var coverURL: String? = extractURL(from: props["Cover Image"])
            if coverURL == nil {
                if let cover = page["cover"] as? [String: Any] {
                    coverURL = (cover["external"] as? [String: Any])?["url"] as? String
                        ?? (cover["file"] as? [String: Any])?["url"] as? String
                }
            }

            return Trip(
                id:             id,
                url:            (page["url"] as? String) ?? "",
                name:           extractTitle(from: props["Trip Name"]) ?? "Untitled",
                location:       extractRichText(from: props["Location"]) ?? "",
                departureDate:  extractDateString(from: props["Departure Date"]),
                returnDate:     extractDateString(from: props["Return Date"]),
                status:         statusStr.flatMap { Trip.TripStatus(rawValue: $0) },
                coverImageURL:  coverURL
            )
        }.sorted { a, b in
            let today = Date()
            let aDate = a.departureDateParsed
            let bDate = b.departureDateParsed
            let aDist = aDate.map { abs($0.timeIntervalSince(today)) } ?? .infinity
            let bDist = bDate.map { abs($0.timeIntervalSince(today)) } ?? .infinity
            return aDist < bDist
        }
    }

    private func parseItems(from data: Data, tripId: String) -> [TripItem] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else { return [] }
        let normalizedTripId = tripId.replacingOccurrences(of: "-", with: "")

        return results.compactMap { page in
            guard let id = page["id"] as? String,
                  let props = page["properties"] as? [String: Any] else { return nil }

            // Filter by trip relation
            let relations = (props["Trip"] as? [String: Any])?["relation"] as? [[String: Any]] ?? []
            guard let linkedId = relations.first?["id"] as? String,
                  linkedId.replacingOccurrences(of: "-", with: "") == normalizedTripId else { return nil }

            let typeStr = extractSelect(from: props["Type"])
            let priorityStr = extractSelect(from: props["Priority"])
            let statusStr = extractSelect(from: props["Status"])
            let checkbox = (props["Reservation Required"] as? [String: Any])?["checkbox"] as? Bool ?? false

            return TripItem(
                id:                  id,
                url:                 (page["url"] as? String) ?? "",
                name:                extractTitle(from: props["Name"]) ?? "Untitled",
                type:                typeStr.flatMap { TripItem.ItemType(rawValue: $0) },
                priority:            priorityStr.flatMap { TripItem.ItemPriority(rawValue: $0) },
                status:              statusStr.flatMap { TripItem.ItemStatus(rawValue: $0) },
                legCity:             extractRichText(from: props["Leg / City"]) ?? extractSelect(from: props["Leg / City"]) ?? "",
                venue:               extractRichText(from: props["Provider / Venue"]) ?? "",
                notes:               extractRichText(from: props["Notes"]) ?? "",
                date:                extractDateString(from: props["Date"]),
                assignedToDate:      extractDateString(from: props["Assigned to Date"]),
                reservationRequired: checkbox,
                tripRelationID:      linkedId
            )
        }
    }

    // MARK: - Extract helpers (duplicated from NotionService per app convention)

    private func extractTitle(from prop: Any?) -> String? {
        guard let arr = (prop as? [String: Any])?["title"] as? [[String: Any]] else { return nil }
        return arr.compactMap { $0["plain_text"] as? String }.joined()
    }

    private func extractRichText(from prop: Any?) -> String? {
        guard let arr = (prop as? [String: Any])?["rich_text"] as? [[String: Any]] else { return nil }
        return arr.compactMap { $0["plain_text"] as? String }.joined()
    }

    private func extractURL(from prop: Any?) -> String? {
        (prop as? [String: Any])?["url"] as? String
    }

    private func extractSelect(from prop: Any?) -> String? {
        (prop as? [String: Any]).flatMap { ($0["select"] as? [String: Any])?["name"] as? String }
    }

    private func extractDateString(from prop: Any?) -> String? {
        (prop as? [String: Any]).flatMap { ($0["date"] as? [String: Any])?["start"] as? String }
    }
}
