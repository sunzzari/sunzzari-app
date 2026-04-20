import Foundation

final class NotionService: @unchecked Sendable {
    static let shared = NotionService()
    private let baseURL = "https://api.notion.com/v1"

    // MARK: - Memory cache
    private var bestOfCache: (entries: [BestOfEntry], at: Date)?
    private var dinosaursCache: (photos: [DinosaurPhoto], at: Date)?
    private var memoriesCache: (memories: [Memory], at: Date)?
    private var restaurantsCache: (items: [Restaurant], at: Date)?
    private var winesCache: (items: [Wine], at: Date)?
    private var activitiesCache: (items: [Activity], at: Date)?
    private var cycleCache: (entries: [CycleEntry], at: Date)?
    private var creditsCache: (entries: [CreditEntry], at: Date)?
    private var infoCache: (entries: [SunzzariInfoEntry], at: Date)?
    private var thoughtsCache: (entries: [ThoughtEntry], at: Date)?
    private let cacheTTL: TimeInterval = 300 // 5 minutes

    func invalidateBestOf() { bestOfCache = nil }
    func invalidateDinosaurs() { dinosaursCache = nil }
    func invalidateMemories() { memoriesCache = nil }
    func invalidateRestaurants() { restaurantsCache = nil }
    func invalidateWines() { winesCache = nil }
    func invalidateActivities() { activitiesCache = nil }
    func invalidateCycle() { cycleCache = nil }
    func invalidateCredits() { creditsCache = nil }
    func invalidateInfo() { infoCache = nil }
    func invalidateThoughts() { thoughtsCache = nil }

    // MARK: - Disk cache

    private var diskCacheDir: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    }

    private func saveToDisk(_ data: Data, name: String) {
        let url = diskCacheDir.appendingPathComponent("sunzzari_\(name).json")
        try? data.write(to: url, options: .atomic)
    }

    private func loadFromDisk(name: String) -> Data? {
        let url = diskCacheDir.appendingPathComponent("sunzzari_\(name).json")
        return try? Data(contentsOf: url)
    }

    // MARK: - Disk cache accessors (instant warm-start, no network)

    func dinosaursDiskCache() -> [DinosaurPhoto]? {
        loadFromDisk(name: "dinosaurs").map { parseDinosaurs(from: $0) }
    }

    func bestOfDiskCache() -> [BestOfEntry]? {
        loadFromDisk(name: "bestof").map { parseBestOf(from: $0) }
    }

    func memoriesDiskCache() -> [Memory]? {
        loadFromDisk(name: "memories").map { parseMemories(from: $0) }
    }

    func restaurantsDiskCache() -> [Restaurant]? {
        loadFromDisk(name: "restaurants").map { parseRestaurants(from: $0) }
    }

    func winesDiskCache() -> [Wine]? {
        loadFromDisk(name: "wines").map { parseWines(from: $0) }
    }

    func activitiesDiskCache() -> [Activity]? {
        loadFromDisk(name: "activities").map { parseActivities(from: $0) }
    }

    func cycleDiskCache() -> [CycleEntry]? {
        loadFromDisk(name: "cycle").map { parseCycleEntries(from: $0) }
    }

    func creditsDiskCache() -> [CreditEntry]? {
        loadFromDisk(name: "credits").map { parseCreditEntries(from: $0) }
    }

    func thoughtsDiskCache() -> [ThoughtEntry]? {
        loadFromDisk(name: "thoughts").map { parseThoughts(from: $0) }
    }

    private var headers: [String: String] {
        [
            "Authorization":   "Bearer \(Constants.Notion.token)",
            "Notion-Version":  Constants.Notion.version,
            "Content-Type":    "application/json"
        ]
    }

    // MARK: - Dinosaurs

    func fetchDinosaurs(force: Bool = false) async throws -> [DinosaurPhoto] {
        if !force, let cached = dinosaursCache, Date().timeIntervalSince(cached.at) < cacheTTL {
            return cached.photos
        }
        do {
            let data = try await queryDatabase(
                id: Constants.Notion.dinosaursDBID,
                sorts: [["property": "Date Added", "direction": "descending"]]
            )
            let photos = parseDinosaurs(from: data)
            dinosaursCache = (photos, Date())
            saveToDisk(data, name: "dinosaurs")
            return photos
        } catch {
            if let diskData = loadFromDisk(name: "dinosaurs") {
                let photos = parseDinosaurs(from: diskData)
                dinosaursCache = (photos, Date())
                return photos
            }
            throw error
        }
    }

    func createDinosaur(_ photo: DinosaurPhoto) async throws {
        try await createPage(body: dinosaurPayload(photo))
    }

    func toggleFavorite(pageID: String, isFavorite: Bool) async throws {
        try await updatePage(id: pageID, body: [
            "properties": ["Favorite": ["checkbox": isFavorite]]
        ])
    }

    func updateDinosaur(_ photo: DinosaurPhoto) async throws {
        try await updatePage(id: photo.id, body: [
            "properties": [
                "Name": titleProp(photo.name),
                "Tags": ["multi_select": photo.tags.map { ["name": $0.rawValue] }]
            ]
        ])
    }

    // MARK: - Memories

    func fetchMemories(force: Bool = false) async throws -> [Memory] {
        if !force, let cached = memoriesCache, Date().timeIntervalSince(cached.at) < cacheTTL {
            return cached.memories
        }
        do {
            let data = try await queryDatabase(
                id: Constants.Notion.memoriesDBID,
                sorts: [["property": "Date", "direction": "descending"]]
            )
            let memories = parseMemories(from: data)
            memoriesCache = (memories, Date())
            saveToDisk(data, name: "memories")
            return memories
        } catch {
            if let diskData = loadFromDisk(name: "memories") {
                let memories = parseMemories(from: diskData)
                memoriesCache = (memories, Date())
                return memories
            }
            throw error
        }
    }

    func createMemory(_ memory: Memory) async throws {
        try await createPage(body: memoryPayload(memory))
    }

    func updateMemory(_ memory: Memory) async throws {
        var props: [String: Any] = [
            "Title":    titleProp(memory.title),
            "Date":     dateProp(memory.date),
            "Category": ["select": ["name": memory.category.rawValue]],
            "Notes":    richTextProp(memory.notes)
        ]
        if let url = memory.photoURL { props["Photo URL"] = ["url": url] }
        try await updatePage(id: memory.id, body: ["properties": props])
    }

    // MARK: - Best Of

    func fetchBestOf(force: Bool = false) async throws -> [BestOfEntry] {
        if !force, let cached = bestOfCache, Date().timeIntervalSince(cached.at) < cacheTTL {
            return cached.entries
        }
        do {
            let data = try await queryDatabase(
                id: Constants.Notion.bestOfDBID,
                sorts: [["property": "Date", "direction": "descending"]]
            )
            let entries = parseBestOf(from: data)
            bestOfCache = (entries, Date())
            saveToDisk(data, name: "bestof")
            return entries
        } catch {
            if let diskData = loadFromDisk(name: "bestof") {
                let entries = parseBestOf(from: diskData)
                bestOfCache = (entries, Date())
                return entries
            }
            throw error
        }
    }

    func createBestOfEntry(_ entry: BestOfEntry) async throws {
        try await createPage(body: bestOfPayload(entry))
    }

    func updateBestOfEntry(_ entry: BestOfEntry) async throws {
        try await updatePage(id: entry.id, body: [
            "properties": [
                "Entry":    titleProp(entry.entry),
                "Date":     dateProp(entry.date),
                "Category": ["select": ["name": entry.category.rawValue]],
                "Notes":    richTextProp(entry.notes)
            ]
        ])
    }

    func archivePage(id: String) async throws {
        try await updatePage(id: id, body: ["archived": true])
    }

    /// Returns year-only Best Of entries (YYYY-01-01 sentinel),
    /// filtered to Funny Moment and Best Bites — used as the notification fallback pool.
    func fetchUnassignedBestOf() async throws -> [BestOfEntry] {
        let all = try await fetchBestOf()
        return all.filter { $0.isYearOnly && ($0.category == .funnyMoment || $0.category == .bestBites) }
    }

    // MARK: - Database cover images

    /// Fetches the cover image URL for a Notion page or database.
    /// Tries GET /pages, GET /databases, then POST /search as a last resort.
    func fetchDatabaseCover(id: String) async throws -> String? {
        func extractCover(_ json: [String: Any]) -> String? {
            guard let cover = json["cover"] as? [String: Any] else { return nil }
            if let external = cover["external"] as? [String: Any] {
                return external["url"] as? String
            }
            if let file = cover["file"] as? [String: Any] {
                return file["url"] as? String
            }
            return nil
        }

        func get(_ endpoint: String) async -> (json: [String: Any]?, status: Int) {
            guard let url = URL(string: "\(baseURL)/\(endpoint)") else { return (nil, 0) }
            var req = URLRequest(url: url)
            req.httpMethod = "GET"
            headers.forEach { req.setValue($1, forHTTPHeaderField: $0) }
            guard let (data, response) = try? await URLSession.shared.data(for: req),
                  let http = response as? HTTPURLResponse else { return (nil, 0) }
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            return (json, http.statusCode)
        }

        // 1. Try pages endpoint (works for regular pages and inline-DB parent pages)
        let pagesResult = await get("pages/\(id)")
        if let json = pagesResult.json, (200...299).contains(pagesResult.status),
           let cover = extractCover(json) { return cover }

        // 2. Try databases endpoint
        let dbResult = await get("databases/\(id)")
        if let json = dbResult.json, (200...299).contains(dbResult.status),
           let cover = extractCover(json) { return cover }

        // 3. Search by ID — try pages first (most common for this app's use),
        //    then databases. Using a hardcoded "database" filter here was a bug:
        //    it excluded page objects entirely, which is what the 3 Hub cover IDs are.
        let searchURL = URL(string: "\(baseURL)/search")!
        var searchReq = URLRequest(url: searchURL)
        searchReq.httpMethod = "POST"
        headers.forEach { searchReq.setValue($1, forHTTPHeaderField: $0) }
        searchReq.httpBody = try? JSONSerialization.data(withJSONObject: [
            "filter": ["value": "page", "property": "object"]
        ])
        if let (data, response) = try? await URLSession.shared.data(for: searchReq),
           let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let results = json["results"] as? [[String: Any]] {
            let normalizedID = id.replacingOccurrences(of: "-", with: "")
            if let match = results.first(where: {
                ($0["id"] as? String)?.replacingOccurrences(of: "-", with: "") == normalizedID
            }) { return extractCover(match) }
        }

        return nil
    }

    // MARK: - Restaurants

    func fetchRestaurants(force: Bool = false) async throws -> [Restaurant] {
        if !force, let cached = restaurantsCache, Date().timeIntervalSince(cached.at) < cacheTTL {
            return cached.items
        }
        do {
            let data = try await queryDatabase(
                id: Constants.Notion.restaurantsDBID,
                sorts: [["property": "Name", "direction": "ascending"]]
            )
            let items = parseRestaurants(from: data)
            restaurantsCache = (items, Date())
            saveToDisk(data, name: "restaurants")
            return items
        } catch {
            if let diskData = loadFromDisk(name: "restaurants") {
                let items = parseRestaurants(from: diskData)
                restaurantsCache = (items, Date())
                return items
            }
            throw error
        }
    }

    func createRestaurant(_ r: Restaurant) async throws {
        try await createPage(body: restaurantPayload(r))
    }

    // MARK: - Wines

    func fetchWines(force: Bool = false) async throws -> [Wine] {
        if !force, let cached = winesCache, Date().timeIntervalSince(cached.at) < cacheTTL {
            return cached.items
        }
        do {
            let data = try await queryDatabase(
                id: Constants.Notion.winesDBID,
                sorts: [["property": "Wine Name", "direction": "ascending"]]
            )
            let items = parseWines(from: data)
            winesCache = (items, Date())
            saveToDisk(data, name: "wines")
            return items
        } catch {
            if let diskData = loadFromDisk(name: "wines") {
                let items = parseWines(from: diskData)
                winesCache = (items, Date())
                return items
            }
            throw error
        }
    }

    func createWine(_ w: Wine) async throws {
        try await createPage(body: winePayload(w))
    }

    // MARK: - Activities

    func fetchActivities(force: Bool = false) async throws -> [Activity] {
        if !force, let cached = activitiesCache, Date().timeIntervalSince(cached.at) < cacheTTL {
            return cached.items
        }
        do {
            let data = try await queryDatabase(
                id: Constants.Notion.activitiesDBID,
                sorts: [["property": "Name", "direction": "ascending"]]
            )
            let items = parseActivities(from: data)
            activitiesCache = (items, Date())
            saveToDisk(data, name: "activities")
            return items
        } catch {
            if let diskData = loadFromDisk(name: "activities") {
                let items = parseActivities(from: diskData)
                activitiesCache = (items, Date())
                return items
            }
            throw error
        }
    }

    func createActivity(_ a: Activity) async throws {
        try await createPage(body: activityPayload(a))
    }

    // MARK: - Cycle Tracker

    func fetchCycleEntries(force: Bool = false) async throws -> [CycleEntry] {
        if !force, let cached = cycleCache, Date().timeIntervalSince(cached.at) < cacheTTL {
            return cached.entries
        }
        do {
            let data = try await queryDatabase(
                id: Constants.Notion.cycleTrackerDBID,
                sorts: [["property": "Period Start", "direction": "descending"]]
            )
            let entries = parseCycleEntries(from: data)
            cycleCache = (entries, Date())
            saveToDisk(data, name: "cycle")
            return entries
        } catch {
            if let diskData = loadFromDisk(name: "cycle") {
                let entries = parseCycleEntries(from: diskData)
                cycleCache = (entries, Date())
                return entries
            }
            throw error
        }
    }

    @discardableResult
    func addCycleEntry(person: CycleEntry.Person, periodStart: Date, avgCycle: Int, notes: String) async throws -> CycleEntry {
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        let title = "\(person.rawValue) — \(fmt.string(from: periodStart))"
        let body: [String: Any] = [
            "parent": ["database_id": Constants.Notion.cycleTrackerDBID],
            "properties": [
                "Name":         titleProp(title),
                "Period Start": dateProp(periodStart),
                "Person":       ["select": ["name": person.rawValue]],
                "Avg Cycle":    ["number": avgCycle],
                "Notes":        richTextProp(notes)
            ]
        ]
        try await createPage(body: body)
        cycleCache = nil
        return CycleEntry(id: UUID().uuidString, periodStart: periodStart,
                          person: person, avgCycle: avgCycle, notes: notes,
                          predictedNext: nil, cycleLength: nil)
    }

    // MARK: - Credits Tracker

    func fetchCredits(force: Bool = false) async throws -> [CreditEntry] {
        if !force, let cached = creditsCache, Date().timeIntervalSince(cached.at) < cacheTTL {
            return cached.entries
        }
        do {
            let data = try await queryDatabase(
                id: Constants.Notion.creditsTrackerDBID,
                sorts: [["property": "Credit", "direction": "ascending"]]
            )
            let entries = parseCreditEntries(from: data)
            creditsCache = (entries, Date())
            saveToDisk(data, name: "credits")
            return entries
        } catch {
            if let diskData = loadFromDisk(name: "credits") {
                let entries = parseCreditEntries(from: diskData)
                creditsCache = (entries, Date())
                return entries
            }
            throw error
        }
    }

    func toggleCredit(_ credit: CreditEntry) async throws {
        var props: [String: Any]
        switch credit.frequency {
        case .monthly:
            props = ["Month Used": ["multi_select": credit.monthsUsed.map { ["name": $0] }]]
        case .quarterly, .semiAnnual:
            props = ["Quarter Used": ["multi_select": credit.quartersUsed.map { ["name": $0] }]]
        case .annual, .every4Years:
            props = ["Year Used": ["checkbox": credit.yearUsed]]
        }
        try await updatePage(id: credit.id, body: ["properties": props])
        creditsCache = nil
    }

    // MARK: - Private: API

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
                throw NotionError.httpError((response as? HTTPURLResponse)?.statusCode ?? 0)
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let results = json["results"] as? [[String: Any]] else { break }
            allResults.append(contentsOf: results)

            let hasMore = json["has_more"] as? Bool ?? false
            startCursor = hasMore ? json["next_cursor"] as? String : nil
        } while startCursor != nil

        return try JSONSerialization.data(withJSONObject: ["results": allResults])
    }

    private func createPage(body: [String: Any]) async throws {
        let url = URL(string: "\(baseURL)/pages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw NotionError.httpError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
    }

    private func updatePage(id: String, body: [String: Any]) async throws {
        let url = URL(string: "\(baseURL)/pages/\(id)")!
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw NotionError.httpError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
    }

    // MARK: - Fetch: Info

    func fetchSunzzariInfo(force: Bool = false) async throws -> [SunzzariInfoEntry] {
        if !force, let cached = infoCache, Date().timeIntervalSince(cached.at) < 300 {
            return cached.entries
        }
        let url = URL(string: "\(baseURL)/databases/\(Constants.Notion.sunzzariInfoDBID)/query")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        request.httpBody = try JSONSerialization.data(withJSONObject: [:])
        let (data, _) = try await URLSession.shared.data(for: request)
        let entries = parseInfoEntries(from: data)
        infoCache = (entries, Date())
        return entries
    }

    func fetchInfoBlocks(pageID: String) async throws -> [InfoBlock] {
        let rawBlocks = try await fetchBlockChildren(blockID: pageID)
        var result: [InfoBlock] = []
        for block in rawBlocks {
            guard let type = block["type"] as? String else { continue }
            switch type {
            case "heading_2":
                if let text = extractPlainTextFromBlocks(block[type] as? [String: Any]) {
                    result.append(.heading2(text))
                }
            case "heading_3":
                if let text = extractPlainTextFromBlocks(block[type] as? [String: Any]) {
                    result.append(.heading3(text))
                }
            case "bulleted_list_item":
                if let content = block[type] as? [String: Any] {
                    let text = extractPlainTextFromBlocks(content) ?? ""
                    let url  = extractHrefFromBlocks(content)
                    result.append(.bullet(text: text, url: url))
                }
            case "paragraph":
                if let text = extractPlainTextFromBlocks(block[type] as? [String: Any]), !text.isEmpty {
                    result.append(.paragraph(text))
                }
            case "table":
                guard let blockID = block["id"] as? String else { continue }
                let rowBlocks = try await fetchBlockChildren(blockID: blockID)
                let rows: [[String]] = rowBlocks.compactMap { row in
                    guard let cells = (row["table_row"] as? [String: Any])?["cells"] as? [[[String: Any]]] else { return nil }
                    return cells.map { cell in
                        cell.compactMap { $0["plain_text"] as? String }.joined()
                    }
                }
                if !rows.isEmpty { result.append(.tableGrid(rows: rows)) }
            default:
                break
            }
        }
        return result
    }

    func fetchBlockChildren(blockID: String) async throws -> [[String: Any]] {
        var all: [[String: Any]] = []
        var cursor: String? = nil
        repeat {
            var urlStr = "\(baseURL)/blocks/\(blockID)/children?page_size=100"
            if let c = cursor { urlStr += "&start_cursor=\(c)" }
            let url = URL(string: urlStr)!
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { break }
            if let results = json["results"] as? [[String: Any]] { all += results }
            cursor = (json["has_more"] as? Bool == true) ? (json["next_cursor"] as? String) : nil
        } while cursor != nil
        return all
    }

    private func extractPlainTextFromBlocks(_ obj: [String: Any]?) -> String? {
        guard let rtArr = obj?["rich_text"] as? [[String: Any]] else { return nil }
        let text = rtArr.compactMap { $0["plain_text"] as? String }.joined()
        return text.isEmpty ? nil : text
    }

    private func extractHrefFromBlocks(_ obj: [String: Any]?) -> String? {
        guard let rtArr = obj?["rich_text"] as? [[String: Any]] else { return nil }
        return rtArr.compactMap { ($0["text"] as? [String: Any])?["link"] as? [String: Any] }
                    .compactMap { $0["url"] as? String }
                    .first
    }

    // MARK: - Private: Parser (Info)

    private func parseInfoEntries(from data: Data) -> [SunzzariInfoEntry] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else { return [] }
        return results.compactMap { page in
            guard let id = page["id"] as? String,
                  let props = page["properties"] as? [String: Any] else { return nil }
            let catStr = extractSelect(from: props["Category"]) ?? "Other"
            let tags = extractMultiSelect(from: props["Tags"])
            return SunzzariInfoEntry(
                id:       id,
                title:    extractTitle(from: props["Name"]) ?? "Untitled",
                category: SunzzariInfoEntry.Category(rawValue: catStr) ?? .other,
                tags:     tags
            )
        }
    }

    // MARK: - Private: Parsers

    private func parseDinosaurs(from data: Data) -> [DinosaurPhoto] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else { return [] }
        return results.compactMap { page in
            guard let id = page["id"] as? String,
                  let props = page["properties"] as? [String: Any] else { return nil }
            let tagStrings = extractMultiSelect(from: props["Tags"])
            let tags = tagStrings.compactMap { DinosaurPhoto.Tag(rawValue: $0) }
            return DinosaurPhoto(
                id:            id,
                name:          extractTitle(from: props["Name"]) ?? "Untitled",
                cloudinaryURL: extractURL(from: props["Cloudinary URL"]),
                dateAdded:     extractDate(from: props["Date Added"]),
                isFavorite:    (props["Favorite"] as? [String: Any])?["checkbox"] as? Bool ?? false,
                tags:          tags
            )
        }
    }

    private func parseMemories(from data: Data) -> [Memory] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else { return [] }
        return results.compactMap { page in
            guard let id = page["id"] as? String,
                  let props = page["properties"] as? [String: Any],
                  let date = extractDate(from: props["Date"]) else { return nil }
            let catStr = extractSelect(from: props["Category"]) ?? "Memory"
            return Memory(
                id:       id,
                title:    extractTitle(from: props["Title"]) ?? "Untitled",
                date:     date,
                category: Memory.Category(rawValue: catStr) ?? .memory,
                notes:    extractRichText(from: props["Notes"]) ?? "",
                photoURL: extractURL(from: props["Photo URL"])
            )
        }
    }

    private func parseBestOf(from data: Data) -> [BestOfEntry] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else { return [] }
        return results.compactMap { page in
            guard let id = page["id"] as? String,
                  let props = page["properties"] as? [String: Any],
                  let date = extractDate(from: props["Date"]) else { return nil }
            let catStr = extractSelect(from: props["Category"]) ?? "Funny Moment"
            return BestOfEntry(
                id:       id,
                entry:    extractTitle(from: props["Entry"]) ?? "Untitled",
                date:     date,
                category: BestOfEntry.Category(rawValue: catStr) ?? .funnyMoment,
                notes:    extractRichText(from: props["Notes"]) ?? ""
            )
        }
    }

    // MARK: - Private: Parsers (Hub)

    private func parseRestaurants(from data: Data) -> [Restaurant] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else { return [] }
        return results.compactMap { page in
            guard let id = page["id"] as? String,
                  let props = page["properties"] as? [String: Any] else { return nil }
            let prefStr = extractSelect(from: props["Preference"])
            return Restaurant(
                id:           id,
                name:         extractTitle(from: props["Name"]) ?? "Untitled",
                beenThere:    (props["Been There?"] as? [String: Any])?["checkbox"] as? Bool ?? false,
                preference:   prefStr.flatMap { Restaurant.Preference(rawValue: $0) },
                location:     extractSelect(from: props["Location"]) ?? "",
                neighborhood: extractRichText(from: props["Neighborhood"]) ?? "",
                goodFor:      extractMultiSelect(from: props["Good For"]),
                topDishes:    extractRichText(from: props["Top Dishes"]) ?? "",
                comments:     extractRichText(from: props["Comments"]) ?? ""
            )
        }
    }

    private func parseWines(from data: Data) -> [Wine] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else { return [] }
        return results.compactMap { page in
            guard let id = page["id"] as? String,
                  let props = page["properties"] as? [String: Any] else { return nil }
            let typeStr = extractSelect(from: props["Wine Type"]) ?? "Red"
            return Wine(
                id:              id,
                wineName:        extractTitle(from: props["Wine Name"]) ?? "Untitled",
                producer:        extractRichText(from: props["Producer"]) ?? "",
                vintage:         (props["Vintage"] as? [String: Any])?["number"] as? Int,
                region:          extractRichText(from: props["Region"]) ?? "",
                wineType:        Wine.WineType(rawValue: typeStr) ?? .red,
                purchaseLocation: extractSelect(from: props["Purchase Location"]).flatMap { Wine.PurchaseLocation(rawValue: $0) },
                cost:            (props["Cost"] as? [String: Any])?["number"] as? Double,
                rating:          extractSelect(from: props["Rating"]).flatMap { Wine.Rating(rawValue: $0) },
                notes:           extractRichText(from: props["Notes"]) ?? "",
                useForCooking:   (props["Use for Cooking"] as? [String: Any])?["checkbox"] as? Bool ?? false
            )
        }
    }

    private func parseActivities(from data: Data) -> [Activity] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else { return [] }
        return results.compactMap { page in
            guard let id = page["id"] as? String,
                  let props = page["properties"] as? [String: Any] else { return nil }
            return Activity(
                id:             id,
                name:           extractTitle(from: props["Name"]) ?? "Untitled",
                location:       extractRichText(from: props["Location"]) ?? "",
                dateSpecific:   (props["Date-Specific?"] as? [String: Any])?["checkbox"] as? Bool ?? false,
                dateActive:     extractDate(from: props["Date Active"]),
                active:         (props["Active?"] as? [String: Any])?["checkbox"] as? Bool ?? false,
                seasonal:       (props["Seasonal?"] as? [String: Any])?["checkbox"] as? Bool ?? false,
                home:           (props["Home?"] as? [String: Any])?["checkbox"] as? Bool ?? false,
                calendarSynced: (props["Calendar Synced?"] as? [String: Any])?["checkbox"] as? Bool ?? false
            )
        }
    }

    // MARK: - Private: Parsers (Cycle + Credits)

    private func parseCycleEntries(from data: Data) -> [CycleEntry] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else { return [] }
        return results.compactMap { page in
            guard let id = page["id"] as? String,
                  let props = page["properties"] as? [String: Any],
                  let periodStart = extractDate(from: props["Period Start"]) else { return nil }
            let personStr = extractSelect(from: props["Person"]) ?? "Elisa"
            let avgCycle = (props["Avg Cycle"] as? [String: Any])?["number"] as? Int ?? 28
            return CycleEntry(
                id:            id,
                periodStart:   periodStart,
                person:        CycleEntry.Person(rawValue: personStr) ?? .elisa,
                avgCycle:      avgCycle,
                notes:         extractRichText(from: props["Notes"]) ?? "",
                predictedNext: extractFormulaDate(from: props["Predicted Next Period"]),
                cycleLength:   extractFormulaNumber(from: props["Cycle Length"])
            )
        }
    }

    private func parseCreditEntries(from data: Data) -> [CreditEntry] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else { return [] }
        return results.compactMap { page in
            guard let id = page["id"] as? String,
                  let props = page["properties"] as? [String: Any] else { return nil }

            func multiSelect(_ key: String) -> [String] {
                guard let d = props[key] as? [String: Any],
                      let arr = d["multi_select"] as? [[String: Any]] else { return [] }
                return arr.compactMap { $0["name"] as? String }
            }
            func checkbox(_ key: String) -> Bool {
                (props[key] as? [String: Any])?["checkbox"] as? Bool ?? false
            }

            let cardStr   = extractSelect(from: props["Card"])      ?? ""
            let personStr = extractSelect(from: props["Person"])     ?? "Elisa"
            let freqStr   = extractSelect(from: props["Frequency"])  ?? "Monthly"

            return CreditEntry(
                id:            id,
                credit:        extractTitle(from: props["Credit"]) ?? "Untitled",
                card:          CreditEntry.Card(rawValue: cardStr)       ?? .amexPlatinum,
                person:        CreditEntry.Person(rawValue: personStr)   ?? .elisa,
                frequency:     CreditEntry.Frequency(rawValue: freqStr)  ?? .monthly,
                amountDollars: (props["Value"] as? [String: Any])?["number"] as? Double,
                portalRequired: checkbox("Portal Required"),
                notes:         extractRichText(from: props["Notes"]) ?? "",
                monthsUsed:    multiSelect("Month Used"),
                quartersUsed:  multiSelect("Quarter Used"),
                yearUsed:      checkbox("Year Used")
            )
        }
    }

    // MARK: - Private: Payload builders

    private func dinosaurPayload(_ photo: DinosaurPhoto) -> [String: Any] {
        var props: [String: Any] = [
            "Name":       titleProp(photo.name),
            "Favorite":   ["checkbox": photo.isFavorite],
            "Tags":       ["multi_select": photo.tags.map { ["name": $0.rawValue] }],
            "Date Added": dateProp(photo.dateAdded ?? Date())
        ]
        if let url = photo.cloudinaryURL { props["Cloudinary URL"] = ["url": url] }
        return ["parent": ["database_id": Constants.Notion.dinosaursDBID], "properties": props]
    }

    private func memoryPayload(_ memory: Memory) -> [String: Any] {
        var props: [String: Any] = [
            "Title":    titleProp(memory.title),
            "Date":     dateProp(memory.date),
            "Category": ["select": ["name": memory.category.rawValue]],
            "Notes":    richTextProp(memory.notes)
        ]
        if let url = memory.photoURL { props["Photo URL"] = ["url": url] }
        return ["parent": ["database_id": Constants.Notion.memoriesDBID], "properties": props]
    }

    private func bestOfPayload(_ entry: BestOfEntry) -> [String: Any] {
        [
            "parent": ["database_id": Constants.Notion.bestOfDBID],
            "properties": [
                "Entry":    titleProp(entry.entry),
                "Date":     dateProp(entry.date),
                "Category": ["select": ["name": entry.category.rawValue]],
                "Notes":    richTextProp(entry.notes)
            ]
        ]
    }

    private func restaurantPayload(_ r: Restaurant) -> [String: Any] {
        var props: [String: Any] = [
            "Name":       titleProp(r.name),
            "Been There?": ["checkbox": r.beenThere],
            "Good For":   ["multi_select": r.goodFor.map { ["name": $0] }],
            "Neighborhood": richTextProp(r.neighborhood),
            "Top Dishes": richTextProp(r.topDishes),
            "Comments":   richTextProp(r.comments)
        ]
        if !r.location.isEmpty { props["Location"] = ["select": ["name": r.location]] }
        if let pref = r.preference { props["Preference"] = ["select": ["name": pref.rawValue]] }
        return ["parent": ["database_id": Constants.Notion.restaurantsDBID], "properties": props]
    }

    private func winePayload(_ w: Wine) -> [String: Any] {
        var props: [String: Any] = [
            "Wine Name":     titleProp(w.wineName),
            "Wine Type":     ["select": ["name": w.wineType.rawValue]],
            "Producer":      richTextProp(w.producer),
            "Region":        richTextProp(w.region),
            "Notes":         richTextProp(w.notes),
            "Use for Cooking": ["checkbox": w.useForCooking]
        ]
        if let vintage = w.vintage { props["Vintage"] = ["number": vintage] }
        if let cost = w.cost { props["Cost"] = ["number": cost] }
        if let loc = w.purchaseLocation { props["Purchase Location"] = ["select": ["name": loc.rawValue]] }
        if let rating = w.rating { props["Rating"] = ["select": ["name": rating.rawValue]] }
        return ["parent": ["database_id": Constants.Notion.winesDBID], "properties": props]
    }

    private func activityPayload(_ a: Activity) -> [String: Any] {
        var props: [String: Any] = [
            "Name":            titleProp(a.name),
            "Location":        richTextProp(a.location),
            "Active?":         ["checkbox": a.active],
            "Seasonal?":       ["checkbox": a.seasonal],
            "Home?":           ["checkbox": a.home],
            "Date-Specific?":  ["checkbox": a.dateSpecific],
            "Calendar Synced?": ["checkbox": a.calendarSynced]
        ]
        if a.dateSpecific, let date = a.dateActive { props["Date Active"] = dateProp(date) }
        return ["parent": ["database_id": Constants.Notion.activitiesDBID], "properties": props]
    }

    // MARK: - Private: Property helpers

    private func titleProp(_ text: String) -> [String: Any] {
        ["title": [["text": ["content": text]]]]
    }

    private func richTextProp(_ text: String) -> [String: Any] {
        ["rich_text": [["text": ["content": text]]]]
    }

    private func dateProp(_ date: Date) -> [String: Any] {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return ["date": ["start": fmt.string(from: date)]]
    }

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

    private func extractDate(from prop: Any?) -> Date? {
        guard let dateStr = (prop as? [String: Any]).flatMap({ ($0["date"] as? [String: Any])?["start"] as? String })
        else { return nil }
        let fmtFull = DateFormatter(); fmtFull.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        let fmtDate = DateFormatter(); fmtDate.dateFormat = "yyyy-MM-dd"
        return fmtFull.date(from: dateStr) ?? fmtDate.date(from: dateStr)
    }

    private func extractSelect(from prop: Any?) -> String? {
        (prop as? [String: Any]).flatMap { ($0["select"] as? [String: Any])?["name"] as? String }
    }

    private func extractMultiSelect(from prop: Any?) -> [String] {
        guard let items = (prop as? [String: Any])?["multi_select"] as? [[String: Any]] else { return [] }
        return items.compactMap { $0["name"] as? String }
    }

    private func extractFormulaDate(from prop: Any?) -> Date? {
        guard let formula = (prop as? [String: Any])?["formula"] as? [String: Any],
              let dateObj = formula["date"] as? [String: Any],
              let start = dateObj["start"] as? String else { return nil }
        let fmtFull = DateFormatter(); fmtFull.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        let fmtDate = DateFormatter(); fmtDate.dateFormat = "yyyy-MM-dd"
        return fmtFull.date(from: start) ?? fmtDate.date(from: start)
    }

    private func extractFormulaNumber(from prop: Any?) -> Int? {
        guard let formula = (prop as? [String: Any])?["formula"] as? [String: Any] else { return nil }
        if let n = formula["number"] as? Int    { return n }
        if let n = formula["number"] as? Double { return Int(n) }
        return nil
    }

    // MARK: - Thought-Action

    func fetchThoughts(force: Bool = false) async throws -> [ThoughtEntry] {
        if !force, let cached = thoughtsCache, Date().timeIntervalSince(cached.at) < cacheTTL {
            return cached.entries
        }
        do {
            let data = try await queryDatabase(
                id: Constants.Notion.thoughtActionDBID,
                sorts: [["timestamp": "created_time", "direction": "descending"]]
            )
            let entries = parseThoughts(from: data)
            thoughtsCache = (entries, Date())
            saveToDisk(data, name: "thoughts")
            return entries
        } catch {
            if let diskData = loadFromDisk(name: "thoughts") {
                let entries = parseThoughts(from: diskData)
                thoughtsCache = (entries, Date())
                return entries
            }
            throw error
        }
    }

    func addThought(content: String, author: String) async throws {
        try await createPage(body: thoughtPayload(content: content, author: author))
        invalidateThoughts()
    }

    private func thoughtPayload(content: String, author: String) -> [String: Any] {
        [
            "parent": ["database_id": Constants.Notion.thoughtActionDBID],
            "properties": [
                "Entry":  titleProp(content),
                "Author": ["select": ["name": author]],
                "Date":   dateProp(Date())
            ]
        ]
    }

    private func parseThoughts(from data: Data) -> [ThoughtEntry] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else { return [] }
        let fmtFull = DateFormatter(); fmtFull.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        let fmtAlt  = DateFormatter(); fmtAlt.dateFormat  = "yyyy-MM-dd'T'HH:mm:ssZ"
        return results.compactMap { page in
            guard let id = page["id"] as? String,
                  let props = page["properties"] as? [String: Any] else { return nil }
            let createdStr = page["created_time"] as? String ?? ""
            let date = fmtFull.date(from: createdStr) ?? fmtAlt.date(from: createdStr) ?? Date()
            return ThoughtEntry(
                id:      id,
                content: extractTitle(from: props["Entry"]) ?? "",
                author:  extractSelect(from: props["Author"]) ?? "Hummingbird",
                date:    date
            )
        }
    }

    enum NotionError: LocalizedError {
        case httpError(Int)
        var errorDescription: String? {
            switch self { case .httpError(let code): return "Notion API error: HTTP \(code)" }
        }
    }
}
