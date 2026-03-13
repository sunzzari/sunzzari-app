import Foundation

struct BestOfEntry: Identifiable {
    let id: String
    var entry: String
    var date: Date
    var category: Category
    var notes: String

    enum Category: String, CaseIterable {
        case funnyMoment    = "Funny Moment"
        case bestBites      = "Best Bites"
        case bestMoments    = "Best Moments"
        case bestLADates    = "Best LA Dates"
        case bestShow       = "Best Show"
        case bestMovie      = "Best Movie"
        case worstMovie     = "Worst Movie"
        case bestRestaurant = "Best Restaurant"
        case favoriteTrip   = "Favorite Trip"
        case favoriteGift   = "Favorite Gift"
        case bestPurchase   = "Best Purchase"
        case improvements   = "Improvements"

        var emoji: String {
            switch self {
            case .funnyMoment:    return "😂"
            case .bestBites:      return "🍜"
            case .bestMoments:    return "✨"
            case .bestLADates:    return "🌴"
            case .bestShow:       return "📺"
            case .bestMovie:      return "🎬"
            case .worstMovie:     return "💀"
            case .bestRestaurant: return "🍽️"
            case .favoriteTrip:   return "✈️"
            case .favoriteGift:   return "🎁"
            case .bestPurchase:   return "🛍️"
            case .improvements:   return "🌱"
            }
        }

        var colorHex: String {
            switch self {
            case .funnyMoment:    return "#FFD93D"
            case .bestBites:      return "#FF9F43"
            case .bestMoments:    return "#54A0FF"
            case .bestLADates:    return "#FF6B9D"
            case .bestShow:       return "#C77DFF"
            case .bestMovie:      return "#70C17C"
            case .worstMovie:     return "#FF6B6B"
            case .bestRestaurant: return "#26C6A4"
            case .favoriteTrip:   return "#A0AEC0"
            case .favoriteGift:   return "#F8A5C2"
            case .bestPurchase:   return "#B8864E"
            case .improvements:   return "#95AAB9"
            }
        }
    }

    var year: Int {
        Calendar(identifier: .gregorian).component(.year, from: date)
    }

    /// True when the entry has no meaningful date at all (1996-01-01 sentinel).
    var isUnassigned: Bool { year == 1996 }

    /// True when only the year is known — day and month are Jan 1 placeholder.
    /// Includes both year-only entries (YYYY-01-01) AND unassigned ones (1996-01-01).
    var isYearOnly: Bool {
        let cal = Calendar(identifier: .gregorian)
        return cal.component(.month, from: date) == 1 && cal.component(.day, from: date) == 1
    }
}
