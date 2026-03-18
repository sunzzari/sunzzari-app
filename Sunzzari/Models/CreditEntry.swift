import Foundation

struct CreditEntry: Identifiable, Codable {
    let id: String
    var credit: String
    var card: Card
    var person: Person
    var frequency: Frequency
    var amountDollars: Double?
    var portalRequired: Bool
    var notes: String
    // Period tracking (multi_select arrays + annual checkbox)
    var monthsUsed: [String]      // e.g. ["Jan", "Mar"]
    var quartersUsed: [String]    // e.g. ["Q1", "Q3"]
    var yearUsed: Bool

    // Returns true if the current calendar period is already marked used
    var isCurrentPeriodUsed: Bool {
        let cal   = Calendar(identifier: .gregorian)
        let month = cal.component(.month, from: Date())
        let q     = (month - 1) / 3 + 1
        let monthNames = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]
        switch frequency {
        case .monthly:
            return monthsUsed.contains(monthNames[month - 1])
        case .quarterly:
            return quartersUsed.contains("Q\(q)")
        case .semiAnnual:
            // H1 tracked as "Q1", H2 tracked as "Q3" in Quarter Used multi_select
            let halfKey = month <= 6 ? "Q1" : "Q3"
            return quartersUsed.contains(halfKey)
        case .annual, .every4Years:
            return yearUsed
        }
    }

    enum Card: String, CaseIterable, Codable {
        case amexPlatinum  = "Amex Platinum"
        case chaseSapphire = "Chase Sapphire Preferred"
        case ventureX      = "Venture X"
        case biltPalladium = "Bilt Palladium"

        var colorHex: String {
            switch self {
            case .amexPlatinum:  return "#60A5FA"
            case .chaseSapphire: return "#1E3A8A"
            case .ventureX:      return "#A78BFA"
            case .biltPalladium: return "#34D399"
            }
        }

        var shortName: String {
            switch self {
            case .amexPlatinum:  return "Platinum"
            case .chaseSapphire: return "CSP"
            case .ventureX:      return "Venture X"
            case .biltPalladium: return "Bilt"
            }
        }
    }

    enum Person: String, CaseIterable, Codable {
        case both  = "Both"
        case elisa = "Elisa"
        case cathy = "Cathy"
    }

    enum Frequency: String, CaseIterable, Codable {
        case monthly     = "Monthly"
        case quarterly   = "Quarterly"
        case semiAnnual  = "Semi-Annual"
        case annual      = "Annual"
        case every4Years = "4-Year"   // matches Notion option name

        var colorHex: String {
            switch self {
            case .monthly:     return "#FBBF24"
            case .quarterly:   return "#60A5FA"
            case .semiAnnual:  return "#A78BFA"
            case .annual:      return "#34D399"
            case .every4Years: return "#F87171"
            }
        }

        var shortLabel: String {
            switch self {
            case .monthly:     return "Monthly"
            case .quarterly:   return "Quarterly"
            case .semiAnnual:  return "Semi-Annual"
            case .annual:      return "Annual"
            case .every4Years: return "Every 4 Yrs"
            }
        }
    }
}
