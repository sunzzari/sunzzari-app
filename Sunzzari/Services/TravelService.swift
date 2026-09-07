import Foundation
import MapKit
import CryptoKit

final class TravelService: @unchecked Sendable {
    static let shared = TravelService()
    private let baseURL = "https://api.notion.com/v1"

    // Bump this when geocoding logic changes to clear stale caches
    // v7: cache values carry a text hash so edited venues re-geocode
    private static let geocodeVersion = 7
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

    // The itinerary HTML disk cache was REMOVED 2026-09-06. That page became a
    // filterable map that needs its JavaScript, so a saved HTML string re-rendered
    // with loadHTMLString would show a dead page. ItineraryWebView now loads the
    // live URL, and offline is TripTodayView's job: native, disk-cached, own map.

    // MARK: - Headers

    private var headers: [String: String] {
        [
            "Authorization":   "Bearer \(Constants.Notion.token)",
            "Notion-Version":  Constants.Notion.version,
            "Content-Type":    "application/json"
        ]
    }

    // MARK: - Fetch Trips

    /// isOffline is returned per-call (not stored on the singleton) so two
    /// concurrent fetches — e.g. the trip list and a trip detail — can't
    /// cross-contaminate each other's offline banners.
    func fetchTrips(force: Bool = false) async throws -> (trips: [Trip], isOffline: Bool) {
        if !force, let cached = tripsCache, Date().timeIntervalSince(cached.at) < cacheTTL {
            return (cached.trips, false)
        }
        do {
            let data = try await queryDatabase(
                id: Constants.Travel.tripsDBID,
                sorts: [["property": "Departure Date", "direction": "descending"]]
            )
            let trips = parseTrips(from: data)
            tripsCache = (trips, Date())
            saveToDisk(data, name: "trips")
            return (trips, false)
        } catch {
            if let diskData = loadFromDisk(name: "trips") {
                let trips = parseTrips(from: diskData)
                tripsCache = (trips, Date())
                return (trips, true)
            }
            throw error
        }
    }

    // MARK: - Fetch Trip Items

    func fetchTripItems(tripId: String, force: Bool = false) async throws -> (items: [TripItem], isOffline: Bool) {
        let normalized = tripId.replacingOccurrences(of: "-", with: "")
        if !force, let cached = itemsCache[tripId], Date().timeIntervalSince(cached.at) < cacheTTL {
            return (cached.items, false)
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
            return (items, false)
        } catch {
            if let diskData = loadFromDisk(name: "items_\(normalized)") {
                let items = parseItems(from: diskData, tripId: tripId)
                itemsCache[tripId] = (items, Date())
                return (items, true)
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
            if let (lat, lon) = Self.cachedCoords(cached, for: result[i]) {
                result[i].latitude = lat
                result[i].longitude = lon
            }
        }
        return result
    }

    // Cached geocode values are "lat,lon|textHash". The hash covers the text
    // fed to the geocoder, so editing a venue in Notion invalidates just that
    // item's coordinate instead of requiring an app-wide geocodeVersion bump.
    private static func geoTextHash(_ item: TripItem) -> String {
        var h: UInt64 = 0xcbf29ce484222325 // FNV-1a: stable across launches
        for b in "\(item.venue)|\(item.name)|\(item.legCity)".utf8 {
            h = (h ^ UInt64(b)) &* 0x100000001b3
        }
        return String(h, radix: 16)
    }

    private static func cachedCoords(_ cached: String, for item: TripItem) -> (Double, Double)? {
        let pieces = cached.split(separator: "|")
        guard pieces.count == 2, String(pieces[1]) == geoTextHash(item) else { return nil }
        let parts = pieces[0].split(separator: ",")
        guard parts.count == 2, let lat = Double(parts[0]), let lon = Double(parts[1]) else { return nil }
        return (lat, lon)
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
                } else if let (lat, lon) = Self.cachedCoords(cached, for: item) {
                    result[index].latitude = lat
                    result[index].longitude = lon
                    continue
                }
                // Stale text hash falls through and re-geocodes.
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
                        UserDefaults.standard.set("\(lat),\(lon)|\(Self.geoTextHash(result[index]))", forKey: key)
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

    // MARK: - Create a trip item (the only write path in this service)

    enum TripItemWriteError: LocalizedError {
        case offline
        case http(Int)
        case readBackFailed(String)

        var errorDescription: String? {
            switch self {
            case .offline:
                return "No connection. Nothing was saved - your text is still here, try again when you have signal."
            case .http(let code):
                return "Notion rejected the write (HTTP \(code)). Nothing was saved."
            case .readBackFailed(let detail):
                return "Saved, but it did not read back correctly: \(detail). Check it in Notion."
            }
        }
    }

    /// Where a quick-added item lands. These two are the only options the app
    /// offers: `Confirmed` is deliberately absent, because a trip item is never
    /// upgraded to Confirmed without explicit approval and a phone form cannot
    /// carry that decision.
    enum QuickAddPlacement {
        /// Planned for a specific day. Status `Assigned` REQUIRES `Assigned to Date`.
        case onDay(String)
        /// Captured, no date yet. Status `Shortlisted`, no date.
        case saveForLater

        var status: TripItem.ItemStatus {
            switch self {
            case .onDay:        return .assigned
            case .saveForLater: return .shortlisted
            }
        }

        var date: String? {
            switch self {
            case .onDay(let d): return d
            case .saveForLater: return nil
            }
        }
    }

    /// Creates a Trip Item in Notion and reads it back before reporting success.
    ///
    /// The read-back is not belt-and-braces: a 200 from Notion says the request
    /// was accepted, not that Status and `Assigned to Date` ended up consistent,
    /// and an Assigned item with no date silently vanishes from the By Day view,
    /// the itinerary and this screen.
    func createTripItem(
        tripId: String,
        name: String,
        type: TripItem.ItemType,
        placement: QuickAddPlacement,
        legCity: String,
        timeText: String,
        notes: String
    ) async throws -> TripItem {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { throw TripItemWriteError.readBackFailed("empty name") }

        var properties: [String: Any] = [
            "Name": ["title": [["text": ["content": trimmedName]]]],
            "Type": ["select": ["name": type.rawValue]],
            "Status": ["select": ["name": placement.status.rawValue]],
            "Priority": ["select": ["name": TripItem.ItemPriority.high.rawValue]],
            "Trip": ["relation": [["id": tripId]]],
        ]
        if let date = placement.date {
            properties["Assigned to Date"] = ["date": ["start": date]]
        }
        if !legCity.isEmpty {
            properties["Leg / City"] = ["rich_text": [["text": ["content": legCity]]]]
        }
        let trimmedTime = timeText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTime.isEmpty {
            properties["Time"] = ["rich_text": [["text": ["content": trimmedTime]]]]
        }
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedNotes.isEmpty {
            properties["Notes"] = ["rich_text": [["text": ["content": trimmedNotes]]]]
        }
        // Link the leg ONLY on an exact match against a leg that already exists.
        // Legs are a fixed universe set at trip start; blank beats a wrong link.
        if let legID = await matchingLegID(tripId: tripId, legCity: legCity) {
            properties["Leg"] = ["relation": [["id": legID]]]
        }

        let body: [String: Any] = [
            "parent": ["database_id": Constants.Travel.itemsDBID],
            "properties": properties,
        ]

        let url = URL(string: "\(baseURL)/pages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            // Fail loud. Never queue silently: a write she believes happened and
            // cannot find later is worse than one that plainly refused.
            throw TripItemWriteError.offline
        }
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw TripItemWriteError.http((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let newID = json["id"] as? String else {
            throw TripItemWriteError.readBackFailed("no page id came back")
        }

        // Read-back gate.
        let created = try await fetchSingleItem(pageID: newID, tripId: tripId)
        guard let created else { throw TripItemWriteError.readBackFailed("could not re-read the new item") }
        guard created.status == placement.status else {
            throw TripItemWriteError.readBackFailed("status is \(created.status?.rawValue ?? "blank")")
        }
        if placement.date != nil, created.displayDate == nil {
            throw TripItemWriteError.readBackFailed("no date landed on an Assigned item")
        }

        invalidateItems(tripId: tripId)
        return created
    }

    /// Exact-match a leg by name for the given trip. Returns nil rather than
    /// guessing, and NEVER creates a leg.
    private func matchingLegID(tripId: String, legCity: String) async -> String? {
        let needle = legCity.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return nil }
        let filter: [String: Any] = ["property": "Trip", "relation": ["contains": tripId]]
        guard let data = try? await queryDatabase(
            id: Constants.Travel.legsDBID,
            sorts: [["property": "Leg Order", "direction": "ascending"]],
            filter: filter
        ),
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let results = json["results"] as? [[String: Any]] else { return nil }

        for page in results {
            guard let id = page["id"] as? String,
                  let props = page["properties"] as? [String: Any] else { continue }
            let candidates = [
                extractTitle(from: props["Leg Name"]),
                extractRichText(from: props["City / Region"]),
            ].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            if candidates.contains(needle) { return id }
        }
        return nil
    }

    /// Re-reads one page and parses it with the same parser as a list fetch, so
    /// the read-back tests the real code path rather than a special case.
    private func fetchSingleItem(pageID: String, tripId: String) async throws -> TripItem? {
        let url = URL(string: "\(baseURL)/pages/\(pageID)")!
        var request = URLRequest(url: url)
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw TripItemWriteError.http((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        guard let page = try? JSONSerialization.jsonObject(with: data) else { return nil }
        let wrapped = try JSONSerialization.data(withJSONObject: ["results": [page]])
        return parseItems(from: wrapped, tripId: tripId).first
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
                itineraryURL:   extractURL(from: props["Itinerary URL"]),
                timeZoneID:     extractRichText(from: props["Time Zone"]) ?? ""
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

            // Filter by trip relation. Check EVERY linked trip, not just the
            // first — an item linked to two trips must not vanish from one of
            // them because of Notion's relation ordering.
            let relations = (props["Trip"] as? [String: Any])?["relation"] as? [[String: Any]] ?? []
            guard let linkedId = relations
                .compactMap({ $0["id"] as? String })
                .first(where: { $0.replacingOccurrences(of: "-", with: "") == normalizedTripId })
            else { return nil }

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
                timeText:            extractRichText(from: props["Time"]) ?? "",
                address:             extractRichText(from: props["Address"]) ?? "",
                confirmationNumber:  extractRichText(from: props["Confirmation #"]) ?? "",
                bookedVia:           extractRichText(from: props["Booked Via"]) ?? "",
                reservationRequired: checkbox,
                reservationMade:     (props["Reservation Made"] as? [String: Any])?["checkbox"] as? Bool ?? false,
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
