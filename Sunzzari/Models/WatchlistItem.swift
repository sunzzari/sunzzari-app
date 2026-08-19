import Foundation

/// Movies, shows, and recipes we've talked about. Deliberately three fields — the point of
/// this DB is a shared list both phones can see, not a media log.
struct WatchlistItem: Identifiable, Codable {
    let id: String
    var title: String
    var kind: Kind
    var watched: Bool
    /// Streaming service for a show, Theaters/At Home for a movie. Nil for recipes.
    var location: String?

    enum Kind: String, CaseIterable, Codable {
        case movie  = "Movie"
        case show   = "Show"
        case recipe = "Recipe"

        var listTitle: String {
            switch self {
            case .movie:  return "MOVIES TO WATCH"
            case .show:   return "SHOWS TO WATCH"
            case .recipe: return "HOME COOKING"
            }
        }

        /// Options offered for the `Where` chip when adding.
        var whereOptions: [String] {
            switch self {
            case .movie:  return ["Theaters", "At Home"]
            case .show:   return ["Netflix", "Hulu", "Max", "Disney+", "Prime Video",
                                  "Apple TV+", "Peacock", "Paramount+", "Other"]
            case .recipe: return []
            }
        }

        var whereLabel: String {
            switch self {
            case .movie:  return "Where"
            case .show:   return "Streaming on"
            case .recipe: return ""
            }
        }

        var addPrompt: String {
            switch self {
            case .movie:  return "Movie title"
            case .show:   return "Show title"
            case .recipe: return "Recipe"
            }
        }
    }
}
