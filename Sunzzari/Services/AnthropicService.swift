import Foundation
import UIKit
import CoreLocation

final class AnthropicService: @unchecked Sendable {
    static let shared = AnthropicService()

    private let endpoint = URL(string: "https://sunzzari-backend.vercel.app/api/analyze")!

    // MARK: - Wine Picker (existing)

    private let winePickerSystemPrompt = """
    You are a wine sommelier helping Elisa and Cathy select a wine. Their profile:

    LOVES (all genuinely liked; the first groups are the strongest signals):
    - Red Burgundy / Pinot Noir — her top reds. Village to Grand Cru: Gevrey-Chambertin, Volnay, Auxey-Duresses, Ladoix, Corton, Clos de Vougeot, Nuits-Saint-Georges. Bright red cherry, violet, earth, fine tannins, lively acidity.
    - Roussillon / structured Southern French reds. Favorite wine of all time: Comme Avant – Domaine Modat (Roussillon).
    - Italian Sangiovese — Chianti Classico, Rosso di Montalcino, Brunello. Tart cherry, dried herb, savory, food-friendly acidity.
    - Structured Old World reds beyond Cabernet — Xinomavro (Naoussa, Nebbiolo/Barolo-like), Nebbiolo, Bordeaux (Graves, Saint-Émilion), Côtes du Rhône, Spanish Garnacha.
    - Bold California reds — Napa/Paso Cabernet and red blends, Zinfandel, California Pinot (Booker Fracture, Stag's Leap Artemis, Justin Isosceles, Pride Mountain, Jordan, Hess).
    - Whites — white Burgundy and restrained/unoaked Chardonnay (Meursault, Ladoix, Auxey-Duresses), Vermentino (Sardinia/Gallura), Sancerre and Sauvignon Blanc, Loire Chenin Blanc. Mineral, citrus, stone fruit, crisp, low to no oak.
    - Sparkling — Italian metodo classico / Trentodoc (Ferrari, Pedrotti), Cava, and Champagne. High acidity, fine bead, brioche, mountain minerality.
    - Dry rosé — Provence / Languedoc / Campania style, crisp and light.

    AVOID: overly jammy, very sweet, heavily oaked, light or dilute reds, and generic origin-less mass-market blends.

    Look at the image. Identify every wine you can see. Recommend the 1–2 best matches. Format:
    🏆 TOP PICK: [Producer] [Wine Name] [Vintage if visible]
    Why it fits: [2–3 sentences connecting this wine's style to their preferences]
    Runner-up (if any): [Name only + one-line reason]

    Be direct and confident. If a label is hard to read, note it briefly.
    """

    func analyzeWineImage(_ image: UIImage) async throws -> String {
        guard let compressed = compress(image) else {
            throw AnthropicError.compressionFailed
        }
        let base64 = compressed.base64EncodedString()

        let body: [String: Any] = [
            "model": Constants.Anthropic.model,
            "max_tokens": 512,
            "system": winePickerSystemPrompt,
            "messages": [[
                "role": "user",
                "content": [
                    ["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": base64]],
                    ["type": "text", "text": "Look at this photo. Figure out if it's a grocery shelf, wine shop, restaurant menu, or wine list - then recommend the best wine for us."]
                ]
            ]]
        ]
        return try await sendRequest(body)
    }

    // MARK: - Wine Autofill

    struct WineAutofill {
        var wineName: String = ""
        var producer: String = ""
        var vintage: Int? = nil
        var region: String = ""
        var wineType: Wine.WineType = .red
        var notes: String = ""
    }

    func extractWineInfo(from image: UIImage) async throws -> WineAutofill {
        guard let compressed = compress(image) else {
            throw AnthropicError.compressionFailed
        }
        let base64 = compressed.base64EncodedString()

        let body: [String: Any] = [
            "model": Constants.Anthropic.model,
            "max_tokens": 512,
            "system": "You extract wine label data. Return ONLY valid JSON — no markdown, no explanation.",
            "messages": [[
                "role": "user",
                "content": [
                    ["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": base64]],
                    ["type": "text", "text": """
                    Read this wine label. Return ONLY this JSON object:
                    {
                      "wineName": "name of wine or appellation",
                      "producer": "producer or winery name",
                      "vintage": 2019,
                      "region": "e.g. Burgundy, Tuscany, Napa Valley",
                      "wineType": "Red",
                      "notes": "brief description from label if any"
                    }
                    Rules: wineType must be one of: Red, White, Rosé, Sparkling, Dessert, Other. vintage is an integer or null. Return ONLY the JSON.
                    """]
                ]
            ]]
        ]

        let text = try await sendRequest(body)
        return try parseWineAutofill(text)
    }

    // MARK: - Restaurant Autofill

    struct RestaurantAutofill {
        var name: String = ""
        var location: String = ""
        var neighborhood: String = ""
        var goodFor: [String] = []
        var topDishes: String = ""
        var comments: String = ""
    }

    func extractRestaurantInfo(query: String) async throws -> RestaurantAutofill {
        let locationList = Restaurant.locationOptions.joined(separator: ", ")
        let goodForList = Restaurant.goodForOptions.joined(separator: ", ")

        let body: [String: Any] = [
            "model": Constants.Anthropic.model,
            "max_tokens": 1024,
            "system": "You extract restaurant information. Return ONLY valid JSON — no markdown, no explanation.",
            "messages": [[
                "role": "user",
                "content": [[
                    "type": "text",
                    "text": """
                    Restaurant info: "\(query)"

                    Return ONLY this JSON object:
                    {
                      "name": "exact restaurant name",
                      "location": "city/area from the list",
                      "neighborhood": "specific neighborhood",
                      "goodFor": ["Dinner", "Fine Dining"],
                      "topDishes": "notable dishes or cuisine style",
                      "comments": "brief vibe and notes"
                    }
                    Rules:
                    - location must be one of: \(locationList)
                    - goodFor must only use items from: \(goodForList)
                    - Pick 2–6 goodFor tags that best describe this restaurant
                    - Return ONLY the JSON.
                    """
                ]]
            ]]
        ]

        let text = try await sendRequest(body)
        return try parseRestaurantAutofill(text)
    }

    // MARK: - Restaurant Claude Search

    /// Given a natural-language query, asks Claude to return ordered IDs of matching
    /// restaurants from the passed-in list. Empty array means no match. Throws on
    /// network/parse failure so callers can surface an inline error.
    func searchRestaurants(query: String, restaurants: [Restaurant]) async throws -> [String] {
        // Note: `comments` field intentionally omitted — it's the most personal column
        // (private notes about friends, occasions) and adds minimal ranking signal vs
        // the structured fields below. Keep personal notes on-device.
        let compact: [[String: Any]] = restaurants.map { r in
            var obj: [String: Any] = [
                "id": r.id,
                "name": r.name,
                "beenThere": r.beenThere,
                "location": r.location,
                "neighborhood": r.neighborhood,
                "goodFor": r.goodFor,
                "topDishes": r.topDishes
            ]
            if let pref = r.preference?.rawValue { obj["preference"] = pref }
            return obj
        }
        let corpusData = try JSONSerialization.data(withJSONObject: compact)
        let corpusStr = String(data: corpusData, encoding: .utf8) ?? "[]"

        let system = """
        You filter a restaurant list by a natural-language query. Return ONLY a JSON \
        array of restaurant IDs that match, ordered most-relevant first. Return an \
        empty array [] if none match. No markdown, no prose. Be strict: honor \
        explicit constraints (neighborhood, city, time-of-day via goodFor, \
        been-there status). "beenThere: false" means the user hasn't been there. \
        Prefer preference "Top Choice" and "Great" over "Good" when ranking ties.
        """

        let body: [String: Any] = [
            "model": Constants.Anthropic.model,
            "max_tokens": 1024,
            "system": system,
            "messages": [[
                "role": "user",
                "content": [[
                    "type": "text",
                    "text": """
                    Query: "\(query)"

                    Restaurants:
                    \(corpusStr)

                    Return ONLY the JSON array of matching IDs.
                    """
                ]]
            ]]
        ]

        let text = try await sendRequest(body)
        return try parseIDArray(text)
    }

    // MARK: - Trip Assistant

    func askTripAssistant(
        query: String,
        items: [TripItem],
        trip: Trip,
        userLocation: CLLocationCoordinate2D?
    ) async throws -> TripAssistantResponse {
        let compact: [[String: Any]] = items.map { item in
            var obj: [String: Any] = [
                "id": item.id,
                "name": item.name,
                "legCity": item.legCity,
                "venue": item.venue,
                "notes": item.notes,
                "reservationRequired": item.reservationRequired
            ]
            if let t = item.type { obj["type"] = t.rawValue }
            if let s = item.status { obj["status"] = s.rawValue }
            if let d = item.displayDate { obj["date"] = d }
            if let de = item.displayDateEnd { obj["dateEnd"] = de }
            if let lat = item.latitude { obj["lat"] = lat }
            if let lon = item.longitude { obj["lon"] = lon }
            return obj
        }
        let corpusData = try JSONSerialization.data(withJSONObject: compact)
        let corpusStr = String(data: corpusData, encoding: .utf8) ?? "[]"

        let dateRange = trip.dateRangeDisplay.isEmpty ? "dates unknown" : trip.dateRangeDisplay
        let locationStr = trip.location.isEmpty ? "unknown" : trip.location
        let locationLine: String
        if let loc = userLocation {
            locationLine = "\(loc.latitude), \(loc.longitude)"
        } else {
            locationLine = "unknown"
        }

        let system = """
        You are the Trip Assistant for Elisa and Cathy on their \(trip.name) trip (\(dateRange), \(locationStr)).

        THEIR PREFERENCES:
        - Wine: Top reds are red Burgundy / Pinot Noir (Gevrey-Chambertin, Volnay, Auxey-Duresses, Ladoix, Corton) and Roussillon (Comme Avant). Also Italian Sangiovese (Chianti Classico, Brunello), structured Old World reds beyond Cabernet (Xinomavro, Nebbiolo, Bordeaux, Côtes du Rhône, Garnacha), bold California reds. Whites: white Burgundy / unoaked Chardonnay, Vermentino, Sancerre, Chenin. Sparkling: metodo classico / Trentodoc, Cava, Champagne. Dry rosé. AVOID jammy, sweet, oaky, dilute, generic blends.
        - Food: Mix of Michelin and casual local. Truffles whenever possible. Cheese caves/fromageries. Long lunches OK.
        - Hotels: Modern Marriott (Luxury Collection, Autograph, W) or best-in-class boutique. Clean, fresh, not heavy with antiques.
        - Activities: NO museums, history tours, or heritage walks. Loves hilltop villages at golden hour, sunset boats, coastal walks, wine tastings, food markets, scuba.
        - Logistics: Private driver over rental. Countryside estates for wine country.

        THEIR TRIP ITEMS (use these FIRST):
        \(corpusStr)

        CURRENT LOCATION (if querying "near me"): \(locationLine)

        QUERY: "\(query)"

        Respond with ONLY this JSON object (no markdown, no prose outside JSON):
        {
          "answer": "1-3 sentence direct answer to their question",
          "matchedItemIds": ["...ids from THEIR TRIP ITEMS that are relevant..."],
          "suggestions": [
            {"name": "...", "type": "...", "neighborhood": "...", "reason": "..."}
          ]
        }

        Rules:
        - Factual queries (train times, hotel for night X): answer directly, populate matchedItemIds with relevant items, leave suggestions empty.
        - Find queries with DB hits: answer briefly, populate matchedItemIds ordered by relevance, leave suggestions empty.
        - Find queries with NO DB hits: populate suggestions with 2-3 places from your training knowledge matching the preferences above. matchedItemIds empty.
        - "Near me" = within ~2km of current location. Sort by distance.
        - Never invent items, dates, or IDs. Only use IDs from THEIR TRIP ITEMS.
        """

        let body: [String: Any] = [
            "model": Constants.Anthropic.model,
            "max_tokens": 1024,
            "system": system,
            "messages": [[
                "role": "user",
                "content": [[
                    "type": "text",
                    "text": query
                ]]
            ]]
        ]

        let text = try await sendRequest(body)
        return try parseTripAssistantResponse(text)
    }

    private func parseTripAssistantResponse(_ text: String) throws -> TripAssistantResponse {
        let stripped = text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let jsonStr = extractJSON(from: stripped)
        guard let data = jsonStr.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(TripAssistantResponse.self, from: data)
        else {
            throw AnthropicError.apiError("Could not parse trip assistant response from Claude")
        }
        return decoded
    }

    private func parseIDArray(_ text: String) throws -> [String] {
        // Strip common wrappers first (markdown code fences, leading/trailing whitespace).
        let stripped = text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Prefer strict parse on the cleaned text — catches well-formed responses
        // even when they contain stray brackets in surrounding prose.
        if let data = stripped.data(using: .utf8),
           let arr = try? JSONSerialization.jsonObject(with: data) as? [String] {
            return arr
        }

        // Fallback: extract first [...] span and try again.
        guard let s = stripped.firstIndex(of: "["),
              let e = stripped.lastIndex(of: "]"),
              s < e else {
            throw AnthropicError.apiError("Claude did not return a JSON array")
        }
        let jsonStr = String(stripped[s...e])
        guard let data = jsonStr.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [String]
        else {
            throw AnthropicError.apiError("Could not parse restaurant ID list from Claude")
        }
        return arr
    }

    // MARK: - Private helpers

    private func sendRequest(_ body: [String: Any]) async throws -> String {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(Constants.Status.pushSecret, forHTTPHeaderField: "x-sunzzari-secret")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AnthropicError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            let preview = String(data: data, encoding: .utf8) ?? "unknown"
            throw AnthropicError.apiError("HTTP \(http.statusCode): \(preview.prefix(200))")
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let text = content.first?["text"] as? String
        else { throw AnthropicError.invalidResponse }
        return text
    }

    private func extractJSON(from text: String) -> String {
        if let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}") {
            return String(text[start...end])
        }
        return text
    }

    private func parseWineAutofill(_ text: String) throws -> WineAutofill {
        let jsonStr = extractJSON(from: text)
        guard let data = jsonStr.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw AnthropicError.apiError("Could not parse wine info from Claude") }

        var result = WineAutofill()
        result.wineName = obj["wineName"] as? String ?? ""
        result.producer = obj["producer"] as? String ?? ""
        result.vintage = obj["vintage"] as? Int
        result.region = obj["region"] as? String ?? ""
        result.notes = obj["notes"] as? String ?? ""
        let typeStr = obj["wineType"] as? String ?? "Red"
        result.wineType = Wine.WineType(rawValue: typeStr) ?? .red
        return result
    }

    private func parseRestaurantAutofill(_ text: String) throws -> RestaurantAutofill {
        let jsonStr = extractJSON(from: text)
        guard let data = jsonStr.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw AnthropicError.apiError("Could not parse restaurant info from Claude") }

        var result = RestaurantAutofill()
        result.name = obj["name"] as? String ?? ""
        result.location = obj["location"] as? String ?? ""
        result.neighborhood = obj["neighborhood"] as? String ?? ""
        result.goodFor = obj["goodFor"] as? [String] ?? []
        result.topDishes = obj["topDishes"] as? String ?? ""
        result.comments = obj["comments"] as? String ?? ""
        return result
    }

    private func compress(_ image: UIImage, maxDimension: CGFloat = 1024) -> Data? {
        let size = image.size
        let scale = min(maxDimension / size.width, maxDimension / size.height, 1.0)
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
        return resized.jpegData(compressionQuality: 0.75)
    }

    enum AnthropicError: LocalizedError {
        case compressionFailed
        case invalidResponse
        case apiError(String)

        var errorDescription: String? {
            switch self {
            case .compressionFailed:    return "Could not compress image"
            case .invalidResponse:      return "Unexpected response from Claude"
            case .apiError(let msg):    return msg
            }
        }
    }
}

