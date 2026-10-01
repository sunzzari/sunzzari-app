import Foundation
import MapKit
import CryptoKit

final class TravelService: @unchecked Sendable {
    static let shared = TravelService()
    private let baseURL = "https://api.notion.com/v1"

    private static let geocodeVersion = 9
    private static let geocodeVersionKey = "sunzzari_travel_geocode_version"

    // v9: per-item geocode entries are gone; pins come from the server in one
    // answer per trip and are cached on disk. The bump clears the old entries.
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

    // The itinerary HTML disk cache was removed 2026-09-06 and the webview that
    // used it went on 2026-09-07: the web itinerary became the same filterable
    // day map this app renders natively, so opening it in a webview was a fourth
    // copy of the one screen. Offline is TripTodayView's job.

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

    // MARK: - Pins (from the travel map server)
    //
    // The phone used to geocode every item itself, one request each, through an
    // endpoint that called Google. Google is off and stays off (Elisa,
    // 2026-09-28: no spend beyond the credit), and the website worked the same
    // pins out separately. Now the server answers once for the whole trip
    // (`/api/trips/<id>/pins`: saved pin, then its saved table), the website
    // draws that same answer, and this app caches it on disk for offline.

    private struct TripPin: Codable {
        struct Branch: Codable {
            let address: String
            let lat: Double
            let lng: Double
        }
        let lat: Double
        let lng: Double
        let branches: [Branch]
    }

    private struct PinsAnswer: Codable { let pins: [String: TripPin] }

    private static let pinsEndpoint = "https://elisa-travel-map.vercel.app/api/trips"

    private func pinsDiskName(_ tripId: String) -> String {
        "pins_\(tripId.replacingOccurrences(of: "-", with: ""))"
    }

    private func cachedPins(tripId: String) -> [String: TripPin]? {
        loadFromDisk(name: pinsDiskName(tripId))
            .flatMap { try? JSONDecoder().decode(PinsAnswer.self, from: $0) }?.pins
    }

    private func apply(_ pins: [String: TripPin], to items: [TripItem]) -> [TripItem] {
        var result = items
        for i in result.indices {
            guard let pin = pins[result[i].id] else { continue }
            result[i].latitude = pin.lat
            result[i].longitude = pin.lng
            result[i].branches = pin.branches.isEmpty ? nil : pin.branches.map {
                TripItem.Branch(address: $0.address, latitude: $0.lat, longitude: $0.lng)
            }
        }
        return result
    }

    /// Pins from the last answer on disk. Synchronous, no network: the day
    /// renders with its map before the fresh answer arrives, and offline.
    func applyCachedCoordinates(_ items: [TripItem], tripId: String) -> [TripItem] {
        cachedPins(tripId: tripId).map { apply($0, to: items) } ?? items
    }

    /// Fresh pins for the whole trip in one request. On any failure the items
    /// come back as given (with whatever the disk cache already applied).
    func geocodeItems(_ items: [TripItem], tripId: String) async -> [TripItem] {
        let id = tripId.replacingOccurrences(of: "-", with: "")
        guard let url = URL(string: "\(Self.pinsEndpoint)/\(id)/pins") else { return items }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let answer = try? JSONDecoder().decode(PinsAnswer.self, from: data) else { return items }
        saveToDisk(data, name: pinsDiskName(tripId))
        return apply(answer.pins, to: items)
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
