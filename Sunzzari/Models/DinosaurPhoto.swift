import Foundation

struct DinosaurPhoto: Identifiable {
    let id: String
    var name: String
    var cloudinaryURL: String?
    var dateAdded: Date?
    var isFavorite: Bool
    var tags: [Tag]

    enum Tag: String, CaseIterable {
        case cute     = "Cute"
        case fierce   = "Fierce"
        case silly    = "Silly"
        case romantic = "Romantic"

        var emoji: String {
            switch self {
            case .cute:     return "🥰"
            case .fierce:   return "🔥"
            case .silly:    return "😂"
            case .romantic: return "💛"
            }
        }

        var color: String {
            switch self {
            case .cute:     return "#FFB3C6"
            case .fierce:   return "#FF6B6B"
            case .silly:    return "#FFD93D"
            case .romantic: return "#C77DFF"
            }
        }
    }
}
