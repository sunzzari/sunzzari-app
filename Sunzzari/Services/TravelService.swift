import Foundation
import MapKit

final class TravelService: @unchecked Sendable {
    static let shared = TravelService()
    private let baseURL = "https://api.notion.com/v1"

    // Bump this when geocoding logic changes to clear stale caches
    private static let geocodeVersion = 6
    private static let geocodeVersionKey = "sunzzari_travel_geocode_version"

    // Vercel-side Google Maps geocoder. The web app gets ~100% coverage from
    // this; MKLocalSearch capped iOS at ~30/401 due to undocumented throttling.
    // See elisa-travel-map/lib/geocode.ts and /api/geocode/route.ts.
    private static let geocoderEndpoint = "https://elisa-travel-map.vercel.app/api/geocode"
    private static let maxConcurrentGeocodes = 8

    // Persistent failure marker so we don't re-hammer the API every launch
    // for items that won't resolve. Retried after the interval elapses.
    private static let failureCachePrefix = "FAIL:"
    private static let failureRetryInterval: TimeInterval = 7 * 24 * 60 * 60

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

    // MARK: - Itinerary HTML cache (live route, cached for offline)

    private func itineraryCacheName(_ urlString: String) -> String {
        "itinerary_\(UInt(bitPattern: urlString.hashValue))"
    }

    func itineraryDiskCacheHTML(urlString: String) -> String? {
        let url = diskCacheDir.appendingPathComponent("sunzzari_travel_\(itineraryCacheName(urlString)).html")
        return try? String(contentsOf: url, encoding: .utf8)
    }

    /// Fetch the live itinerary HTML, cache to disk on success, fall back to the
    /// cached copy when offline. Returns nil only when neither network nor cache
    /// has anything to show.
    func fetchItineraryHTML(urlString: String) async -> String? {
        guard let url = URL(string: urlString) else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let html = String(data: data, encoding: .utf8) else {
                return itineraryDiskCacheHTML(urlString: urlString)
            }
            let cacheURL = diskCacheDir.appendingPathComponent("sunzzari_travel_\(itineraryCacheName(urlString)).html")
            try? html.write(to: cacheURL, atomically: true, encoding: .utf8)
            return html
        } catch {
            return itineraryDiskCacheHTML(urlString: urlString)
        }
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
        for i in result.indices where !result[i].hasCoordinates && Self.hasGeocodableText(result[i]) {
            let key = TripItem.geoKey(for: result[i].id)
            guard let cached = UserDefaults.standard.string(forKey: key),
                  !cached.hasPrefix(Self.failureCachePrefix) else { continue }
            let parts = cached.split(separator: ",")
            if parts.count == 2, let lat = Double(parts[0]), let lon = Double(parts[1]) {
                result[i].latitude = lat
                result[i].longitude = lon
            }
        }
        return result
    }

    /// True if the item has any text we can feed to a geocoder. We fall back
    /// to `name` when `venue` is empty because most Notion items put the
    /// place in the title (e.g. "Sacre Coeur", "Pajar") and leave the
    /// Provider/Venue field blank. The previous code skipped those silently,
    /// which produced ~17% map coverage on a 400-item trip.
    private static func hasGeocodableText(_ item: TripItem) -> Bool {
        !item.venue.isEmpty || !item.name.isEmpty
    }

    // MARK: - Geocoding

    func geocodeItems(_ items: [TripItem], tripLocation: String = "") async -> [TripItem] {
        var result = items
        let toGeocode = items.enumerated().filter { !$0.element.hasCoordinates && Self.hasGeocodableText($0.element) }

        var needsNetwork: [(index: Int, item: TripItem)] = []
        let now = Date().timeIntervalSince1970
        for (index, item) in toGeocode {
            let key = TripItem.geoKey(for: item.id)
            if let cached = UserDefaults.standard.string(forKey: key) {
                if cached.hasPrefix(Self.failureCachePrefix) {
                    let ts = TimeInterval(cached.dropFirst(Self.failureCachePrefix.count)) ?? 0
                    if now - ts < Self.failureRetryInterval { continue }
                } else {
                    let parts = cached.split(separator: ",")
                    if parts.count == 2, let lat = Double(parts[0]), let lon = Double(parts[1]) {
                        result[index].latitude = lat
                        result[index].longitude = lon
                        continue
                    }
                }
            }
            needsNetwork.append((index, item))
        }

        // Hit the Vercel /api/geocode endpoint (Google Maps Geocoding API,
        // Redis-cached server-side). 8-wide concurrency is fine since cached
        // hits return instantly and the upstream limit is 50/sec; we never
        // exceed that with 401 items.
        let batchSize = Self.maxConcurrentGeocodes
        var batchStart = 0
        while batchStart < needsNetwork.count {
            let batchEnd = min(batchStart + batchSize, needsNetwork.count)
            let batch = Array(needsNetwork[batchStart..<batchEnd])

            await withTaskGroup(of: (Int, (Double, Double)?).self) { group in
                for (index, item) in batch {
                    group.addTask {
                        let coords = await Self.geocodeItem(item)
                        return (index, coords)
                    }
                }
                for await (index, coords) in group {
                    let key = TripItem.geoKey(for: result[index].id)
                    if let (lat, lon) = coords {
                        result[index].latitude = lat
                        result[index].longitude = lon
                        UserDefaults.standard.set("\(lat),\(lon)", forKey: key)
                    } else {
                        UserDefaults.standard.set("\(Self.failureCachePrefix)\(now)", forKey: key)
                    }
                }
            }
            batchStart = batchEnd
        }

        return result
    }

    // Geocode a single item via the Vercel endpoint. Tries venue first, then
    // name as fallback for items without a Provider/Venue. Returns nil only
    // when every query exhausted; caller caches success or failure.
    private static func geocodeItem(_ item: TripItem) async -> (Double, Double)? {
        if !item.venue.isEmpty,
           let coords = await geocodeViaVercel(query: item.venue, city: item.legCity) {
            return coords
        }
        if !item.name.isEmpty && item.name != item.venue,
           let coords = await geocodeViaVercel(query: item.name, city: item.legCity) {
            return coords
        }
        return nil
    }

    private static func geocodeViaVercel(query: String, city: String) async -> (Double, Double)? {
        guard !query.isEmpty || !city.isEmpty else { return nil }
        guard var components = URLComponents(string: Self.geocoderEndpoint) else { return nil }
        components.queryItems = [
            URLQueryItem(name: "venue", value: query),
            URLQueryItem(name: "city", value: city)
        ]
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return nil
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let lat = json["lat"] as? Double, let lng = json["lng"] as? Double else {
                return nil
            }
            return (lat, lng)
        } catch {
            return nil
        }
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
                coverImageURL:  coverURL,
                itineraryURL:   extractURL(from: props["Itinerary URL"])
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
                dateEnd:             extractDateEndString(from: props["Date"]),
                assignedToDate:      extractDateString(from: props["Assigned to Date"]),
                assignedToDateEnd:   extractDateEndString(from: props["Assigned to Date"]),
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

    private func extractDateEndString(from prop: Any?) -> String? {
        (prop as? [String: Any]).flatMap { ($0["date"] as? [String: Any])?["end"] as? String }
    }
}
