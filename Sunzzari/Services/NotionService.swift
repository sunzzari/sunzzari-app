import Foundation

final class NotionService: @unchecked Sendable {
    static let shared = NotionService()
    private let baseURL = "https://api.notion.com/v1"

    // MARK: - Cache
    private var bestOfCache: (entries: [BestOfEntry], at: Date)?
    private var dinosaursCache: (photos: [DinosaurPhoto], at: Date)?
    private var memoriesCache: (memories: [Memory], at: Date)?
    private let cacheTTL: TimeInterval = 300 // 5 minutes

    func invalidateBestOf() { bestOfCache = nil }
    func invalidateDinosaurs() { dinosaursCache = nil }
    func invalidateMemories() { memoriesCache = nil }

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
        let data = try await queryDatabase(
            id: Constants.Notion.dinosaursDBID,
            sorts: [["property": "Date Added", "direction": "descending"]]
        )
        let photos = parseDinosaurs(from: data)
        dinosaursCache = (photos, Date())
        return photos
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
        let data = try await queryDatabase(
            id: Constants.Notion.memoriesDBID,
            sorts: [["property": "Date", "direction": "descending"]]
        )
        let memories = parseMemories(from: data)
        memoriesCache = (memories, Date())
        return memories
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
        let data = try await queryDatabase(
            id: Constants.Notion.bestOfDBID,
            sorts: [["property": "Date", "direction": "descending"]]
        )
        let entries = parseBestOf(from: data)
        bestOfCache = (entries, Date())
        return entries
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

    enum NotionError: LocalizedError {
        case httpError(Int)
        var errorDescription: String? {
            switch self { case .httpError(let code): return "Notion API error: HTTP \(code)" }
        }
    }
}
