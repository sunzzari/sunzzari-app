import Foundation

struct Restaurant: Identifiable, Codable {
    let id: String
    var name: String
    var beenThere: Bool
    var preference: Preference?
    var location: String
    var neighborhood: String
    var goodFor: [String]
    var topDishes: String
    var comments: String

    enum Preference: String, CaseIterable, Codable {
        case topChoice = "Top Choice"
        case great     = "Great"
        case good      = "Good"
        case bad       = "Bad"

        var colorHex: String {
            switch self {
            case .topChoice: return "#54A0FF"
            case .great:     return "#70C17C"
            case .good:      return "#FBBF24"
            case .bad:       return "#FF6B6B"
            }
        }
    }

    // Coordinate cache keys stored in UserDefaults as "lat,lon"
    static func geoKey(for id: String) -> String { "sunzzari_geo_\(id)" }
}

// Location and Good For options — sourced from Notion DB schema
extension Restaurant {
    static let locationOptions: [String] = [
        "Denver", "East Bay", "Hong Kong", "Joshua Tree", "Koh Samui",
        "LA", "LA / OC", "LA / SF", "Marin", "Maui", "Napa", "NYC",
        "OC", "OC / San Diego", "Paris", "San Diego", "SF", "SF / LA",
        "SF / Marin", "SF / Napa", "Singapore", "Vancouver"
    ]

    static let goodForOptions: [String] = [
        "Coffee", "Breakfast", "Brunch", "Lunch", "Dinner", "Late Night",
        "Happy Hour", "Cocktails", "Wine", "Bar", "Speakeasy", "Rooftop",
        "Outdoor Dining", "Fine Dining", "Tasting Menu", "Street Food",
        "Fast Food", "Take Out", "Bakery", "Pastries", "Dessert", "Snack",
        "Cake", "Pizza", "Ramen", "Sushi", "Dim Sum", "Korean BBQ",
        "Sandwiches", "Tacos", "Seafood", "Steak", "BBQ", "Dumplings",
        "Burger", "Noodles", "Chinese", "Japanese", "Korean", "Thai",
        "Vietnamese", "Italian", "Mexican", "Indian", "French", "Spanish",
        "Peruvian", "Persian", "Filipino", "Taiwanese", "Indonesian",
        "Greek", "Hawaiian", "Salvadorean", "Caribbean", "Middle Eastern",
        "HK Café", "HK BBQ", "Szechuan", "Singaporean", "Puerto Rican",
        "Boba", "Izakaya", "Small Plates", "Vegan", "Asian Fusion",
        "Contemporary American", "Wine Shop", "Cheese Shop"
    ]
}
