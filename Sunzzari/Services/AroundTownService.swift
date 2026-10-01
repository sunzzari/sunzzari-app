import Foundation
import CoreLocation

/// Around Town, from the travel map's server.
///
/// The phone used to read the Restaurant Guide and Activities tables itself,
/// work out each place's region and colour, and geocode every row. The website
/// did all of that a second time in TypeScript, and the two drifted. Elisa,
/// 2026-09-30: "why are the travel map and sunzzari travel maps so diffuse? the
/// same data is used for both and the same features should be used for both".
///
/// So this app no longer decides where a place is. It asks the server for the
/// finished answer (`/api/around-town`), draws it, and keeps the last answer on
/// disk for offline. Looking a place up and saving its address and pin go
/// through the same server routes the website uses (`/api/places*`). Free
/// sources only on the server side: no Google call anywhere on this path.
final class AroundTownService: @unchecked Sendable {
    static let shared = AroundTownService()
    private init() {}

    private static let base = "https://elisa-travel-map.vercel.app"

    // MARK: - Places

    private struct Payload: Decodable { let places: [Place] }

    struct Place: Decodable {
        struct Branch: Decodable {
            let address: String
            let lat: Double
            let lng: Double
        }
        let id: String
        let name: String
        let kind: String
        let region: String?
        let neighborhood: String
        let location: String
        let preference: String?
        let goodFor: [String]
        let topDishes: String
        let comments: String
        let wantToTry: Bool
        let beenThere: Bool
        let address: String
        let baseColor: String
        let lat: Double?
        let lng: Double?
        let fitArea: String?
        let branches: [Branch]
    }

    private var diskURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("sunzzari_around_town.json")
    }

    private func decode(_ data: Data) -> [AroundTownItem]? {
        (try? JSONDecoder().decode(Payload.self, from: data))?.places.map(AroundTownItem.init(place:))
    }

    /// The last answer the server gave, for a first paint and for offline.
    func cachedPlaces() -> [AroundTownItem]? {
        (try? Data(contentsOf: diskURL)).flatMap(decode)
    }

    /// Fresh places from the server. Throws when it cannot be reached or the
    /// answer does not parse; the caller keeps whatever is on disk.
    func fetchPlaces() async throws -> [AroundTownItem] {
        var request = URLRequest(url: URL(string: "\(Self.base)/api/around-town")!)
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200, let items = decode(data) else {
            throw ServiceError.badAnswer
        }
        try? data.write(to: diskURL, options: .atomic)
        return items
    }

    // MARK: - Lookup and save (same routes as the website)

    struct Match: Identifiable, Hashable, Decodable {
        let name: String
        let address: String
        let lat: Double
        let lng: Double
        var id: String { "\(lat),\(lng)" }
    }

    private struct LookupAnswer: Decodable {
        let matches: [Match]
        let note: String?
    }

    private struct SaveAnswer: Decodable {
        struct Location: Decodable { let placed: Bool }
        let location: Location?
    }

    private struct ErrorAnswer: Decodable { let error: String }

    enum ServiceError: LocalizedError {
        case badAnswer
        case server(String)
        var errorDescription: String? {
            switch self {
            case .badAnswer: return "Could not reach the map server. Try again."
            case .server(let message): return message
            }
        }
    }

    private func send(_ request: URLRequest) async throws -> Data {
        var request = request
        // The app proves itself with the Notion key it already carries; the
        // server accepts it only if Notion says that key can open the
        // Restaurant Guide, then forgets it. No extra secret to set up anywhere.
        request.setValue(Constants.Notion.token, forHTTPHeaderField: "x-notion-token")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 20
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else { throw ServiceError.badAnswer }
        guard http.statusCode == 200 else {
            let message = (try? JSONDecoder().decode(ErrorAnswer.self, from: data))?.error
            throw message.map(ServiceError.server) ?? ServiceError.badAnswer
        }
        return data
    }

    /// Up to five candidate places for a name (or a typed street address),
    /// fenced to the place's own area by the server. Nothing is saved from here.
    func lookup(
        query: String, isRestaurant: Bool, neighborhood: String, location: String
    ) async throws -> (matches: [Match], note: String?) {
        var components = URLComponents(string: "\(Self.base)/api/places/lookup")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "kind", value: isRestaurant ? "restaurant" : "activity"),
            URLQueryItem(name: "neighborhood", value: neighborhood),
            URLQueryItem(name: "location", value: location)
        ]
        let data = try await send(URLRequest(url: components.url!))
        guard let answer = try? JSONDecoder().decode(LookupAnswer.self, from: data) else { throw ServiceError.badAnswer }
        return (answer.matches, answer.note)
    }

    /// Saves a place's address and pin. `pin` is the tapped match's spot; with
    /// none, the server pins the typed address itself or saves it unpinned.
    /// Returns whether the place ended up on the map.
    @discardableResult
    func saveLocation(pageID: String, address: String, pin: CLLocationCoordinate2D?) async throws -> Bool {
        let id = pageID.replacingOccurrences(of: "-", with: "")
        var request = URLRequest(url: URL(string: "\(Self.base)/api/places/\(id)")!)
        request.httpMethod = "PATCH"
        var body: [String: Any] = ["address": address]
        if let pin {
            body["lat"] = pin.latitude
            body["lng"] = pin.longitude
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data = try await send(request)
        return (try? JSONDecoder().decode(SaveAnswer.self, from: data))?.location?.placed ?? false
    }
}
