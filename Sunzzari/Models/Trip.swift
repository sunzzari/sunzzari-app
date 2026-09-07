import Foundation

struct Trip: Identifiable, Codable, Hashable {
    let id: String
    let url: String
    var name: String
    var location: String
    var departureDate: String?
    var returnDate: String?
    var status: TripStatus?
    var coverImageURL: String?
    var itineraryURL: String?
    /// IANA zone for the trip, e.g. "America/Denver". Blank falls back to the
    /// device zone. See TripDayPlanner.today(in:).
    var timeZoneID: String = ""

    enum TripStatus: String, Codable, CaseIterable {
        case planning   = "Planning"
        case booked     = "Booked"
        case inProgress = "In Progress"
        case completed  = "Completed"
        case cancelled  = "Cancelled"

        var sortOrder: Int {
            switch self {
            case .inProgress: return 0
            case .planning:   return 1
            case .booked:     return 2
            case .completed:  return 3
            case .cancelled:  return 4
            }
        }

        var colorHex: String {
            switch self {
            case .planning:   return "#3B82F6"
            case .booked:     return "#F59E0B"
            case .inProgress: return "#22C55E"
            case .completed:  return "#6B7280"
            case .cancelled:  return "#EF4444"
            }
        }
    }

    var sortKey: Int {
        status?.sortOrder ?? 5
    }

    var departureDateParsed: Date? {
        guard let departureDate else { return nil }
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.date(from: departureDate)
    }

    var dateRangeDisplay: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let display = DateFormatter()
        display.dateFormat = "MMM d, yyyy"

        var parts: [String] = []
        if let d = departureDate, let date = fmt.date(from: d) {
            parts.append(display.string(from: date))
        }
        if let r = returnDate, let date = fmt.date(from: r) {
            parts.append(display.string(from: date))
        }
        return parts.joined(separator: " - ")
    }
}
