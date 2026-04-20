import Foundation
import UIKit

final class AnthropicService: @unchecked Sendable {
    static let shared = AnthropicService()

    private let endpoint = URL(string: "https://sunzzari-backend.vercel.app/api/analyze")!

    // MARK: - Wine Picker (existing)

    private let winePickerSystemPrompt = """
    You are a wine sommelier helping Elisa and Cathy select a wine. Their profile:

    LOVES: Old World structured reds (Roussillon, Tuscany, Southern Rhône) — bright acidity, mineral backbone, dark cherry, herbal notes, moderate oak. Favorite wine: Comme Avant – Domaine Modat. Italian Sangiovese (Chianti, Chianti Classico). Bold California reds — Napa/Paso Robles Cabernet, Zinfandel (Booker Fracture, Stag's Leap Artemis, Justin Isosceles, Pride Mountain, Saldo Zin). California Pinot Noir. Crisp dry whites (mineral, citrus, stone fruit). Dry rosé. Champagne/dry sparkling.

    AVOID: Overly jammy, very sweet, extremely oaky, light or dilute reds.

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
        let compact: [[String: Any]] = restaurants.map { r in
            var obj: [String: Any] = [
                "id": r.id,
                "name": r.name,
                "beenThere": r.beenThere,
                "location": r.location,
                "neighborhood": r.neighborhood,
                "goodFor": r.goodFor,
                "topDishes": r.topDishes,
                "comments": r.comments
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

    private func parseIDArray(_ text: String) throws -> [String] {
        let start = text.firstIndex(of: "[")
        let end = text.lastIndex(of: "]")
        guard let s = start, let e = end, s < e else {
            throw AnthropicError.apiError("Claude did not return a JSON array")
        }
        let jsonStr = String(text[s...e])
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

