import Foundation
import CoreLocation

struct StatusEntry: Identifiable {
    let id: String           // Notion page ID
    let name: String         // "Hummingbird" | "Branch"
    let mood: Int            // 0–100
    let adjective: String    // e.g. "Happy!", "Tired"
    let moodUpdatedAt: Date?
    let latitude: Double?
    let longitude: Double?
    let locationUpdatedAt: Date?

    var coordinate: CLLocationCoordinate2D? {
        guard let lat = latitude, let lon = longitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    var isHummingbird: Bool { name == "Hummingbird" }

    var moodEmoji: String {
        switch mood {
        case 0...20:  return "😴"
        case 21...40: return "😔"
        case 41...60: return "😊"
        case 61...80: return "🌟"
        default:      return "🔥"
        }
    }

    var moodColorHex: String {
        switch mood {
        case 0...20:  return "#EF4444"
        case 21...40: return "#F97316"
        case 41...60: return "#FBBF24"
        case 61...80: return "#22C55E"
        default:      return "#16A34A"
        }
    }
}
