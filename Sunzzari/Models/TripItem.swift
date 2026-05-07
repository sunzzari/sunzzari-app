import Foundation
import SwiftUI

struct TripItem: Identifiable, Codable {
    let id: String
    let url: String
    var name: String
    var type: ItemType?
    var priority: ItemPriority?
    var status: ItemStatus?
    var legCity: String
    var venue: String
    var notes: String
    var date: String?
    var dateEnd: String?
    var assignedToDate: String?
    var assignedToDateEnd: String?
    var reservationRequired: Bool
    var tripRelationID: String?
    var latitude: Double?
    var longitude: Double?

    var hasCoordinates: Bool { latitude != nil && longitude != nil }

    var displayDate: String? { assignedToDate ?? date }
    var displayDateEnd: String? { assignedToDateEnd ?? dateEnd }

    var displayDateParsed: Date? {
        guard let str = displayDate else { return nil }
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.date(from: str)
    }

    static func geoKey(for id: String) -> String { "sunzzari_travel_geo_\(id)" }

    // MARK: - Enums

    enum ItemType: String, Codable, CaseIterable {
        case hotel     = "Hotel"
        case restaurant = "Restaurant"
        case activity  = "Activity"
        case flight    = "Flight"
        case train     = "Train"
        case ferry     = "Ferry"
        case carRental = "Car Rental"
        case other     = "Other"

        var colorHex: String {
            switch self {
            case .hotel:      return "#3B82F6"
            case .restaurant: return "#EF4444"
            case .activity:   return "#10B981"
            case .flight:     return "#8B5CF6"
            case .train:      return "#F59E0B"
            case .ferry:      return "#06B6D4"
            case .carRental:  return "#F97316"
            case .other:      return "#6B7280"
            }
        }

        var sfSymbol: String {
            switch self {
            case .hotel:      return "bed.double.fill"
            case .restaurant: return "fork.knife"
            case .activity:   return "figure.hiking"
            case .flight:     return "airplane"
            case .train:      return "tram.fill"
            case .ferry:      return "ferry.fill"
            case .carRental:  return "car.fill"
            case .other:      return "mappin"
            }
        }

        var color: Color { Color(hex: colorHex) }

        var sortOrder: Int {
            switch self {
            case .hotel:      return 0
            case .restaurant: return 1
            case .activity:   return 2
            case .flight:     return 3
            case .train:      return 4
            case .ferry:      return 5
            case .carRental:  return 6
            case .other:      return 7
            }
        }
    }

    enum ItemPriority: String, Codable, CaseIterable {
        case must     = "Must"
        case high     = "High"
        case optional = "Optional"

        var colorHex: String {
            switch self {
            case .must:     return "#EF4444"
            case .high:     return "#F97316"
            case .optional: return "#D1D5DB"
            }
        }

        var color: Color { Color(hex: colorHex) }

        var sortOrder: Int {
            switch self {
            case .must:     return 0
            case .high:     return 1
            case .optional: return 2
            }
        }
    }

    enum ItemStatus: String, Codable, CaseIterable {
        case confirmed         = "Confirmed"
        case assigned          = "Assigned"
        case reservationPending = "Reservation Pending"
        case shortlisted       = "Shortlisted"
        case researching       = "Researching"
        case cancelled         = "Cancelled"

        var colorHex: String {
            switch self {
            case .researching:       return "#9CA3AF"
            case .shortlisted:       return "#EAB308"
            case .assigned:          return "#3B82F6"
            case .reservationPending: return "#F97316"
            case .confirmed:         return "#22C55E"
            case .cancelled:         return "#EF4444"
            }
        }

        var color: Color { Color(hex: colorHex) }
    }
}
