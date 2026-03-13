import Foundation

struct Memory: Identifiable {
    let id: String
    var title: String
    var date: Date
    var category: Category
    var notes: String
    var photoURL: String?

    enum Category: String, CaseIterable {
        case memory      = "Memory"
        case milestone   = "Milestone"
        case funnyMoment = "Funny Moment"

        var emoji: String {
            switch self {
            case .memory:      return "💭"
            case .milestone:   return "🌟"
            case .funnyMoment: return "😄"
            }
        }

        var colorHex: String {
            switch self {
            case .memory:      return "#5B9BD5"
            case .milestone:   return "#70C17C"
            case .funnyMoment: return "#FFD93D"
            }
        }
    }

    nonisolated var year: Int {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: "en_US")
        return cal.component(.year, from: date)
    }

    // Returns true if this memory's month+day matches a given date
    nonisolated func occursOn(monthDay date: Date) -> Bool {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: "en_US")
        return cal.component(.month, from: self.date) == cal.component(.month, from: date)
            && cal.component(.day, from: self.date) == cal.component(.day, from: date)
    }
}
