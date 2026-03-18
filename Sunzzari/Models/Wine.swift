import Foundation

struct Wine: Identifiable, Codable {
    let id: String
    var wineName: String
    var producer: String
    var vintage: Int?
    var region: String
    var wineType: WineType
    var purchaseLocation: PurchaseLocation?
    var cost: Double?
    var rating: Rating?
    var notes: String
    var useForCooking: Bool

    enum WineType: String, CaseIterable, Codable {
        case red       = "Red"
        case white     = "White"
        case rose      = "Rosé"
        case sparkling = "Sparkling"
        case dessert   = "Dessert"
        case other     = "Other"

        var colorHex: String {
            switch self {
            case .red:       return "#EF4444"
            case .white:     return "#FBBF24"
            case .rose:      return "#F472B6"
            case .sparkling: return "#60A5FA"
            case .dessert:   return "#FB923C"
            case .other:     return "#8E8E93"
            }
        }
    }

    enum PurchaseLocation: String, CaseIterable, Codable {
        case traderJoes = "Trader Joe's"
        case wholeFoods = "Whole Foods"
        case costco     = "Costco"
        case restaurant = "Restaurant"
        case other      = "Other"
    }

    enum Rating: String, CaseIterable, Codable {
        case five  = "⭐⭐⭐⭐⭐"
        case four  = "⭐⭐⭐⭐"
        case three = "⭐⭐⭐"
        case two   = "⭐⭐"
        case one   = "⭐"

        var stars: Int {
            switch self {
            case .five: return 5; case .four: return 4; case .three: return 3
            case .two:  return 2; case .one:  return 1
            }
        }
    }
}
