import Foundation
import SwiftUI
import CoreLocation

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
    /// Notion `Time`: free text, a clock time or a rough word. See TripTime.
    var timeText: String = ""
    var address: String = ""
    var confirmationNumber: String = ""
    var bookedVia: String = ""
    var reservationRequired: Bool
    var reservationMade: Bool = false
    var tripRelationID: String?
    var latitude: Double?
    var longitude: Double?
    /// A chain's other branches, from the travel map server. Each is drawn as
    /// its own pin that opens this item.
    var branches: [Branch]? = nil

    struct Branch: Codable {
        let address: String
        let latitude: Double
        let longitude: Double
    }

    var hasCoordinates: Bool { latitude != nil && longitude != nil }

    // The map tells pins apart by id, so a branch pin carries its item's id plus
    // a suffix, and every tap is mapped back with `placeID(of:)`. Same scheme as
    // the website (`lib/saved-pins.ts`). Notion ids never contain "~".
    static func branchID(_ itemID: String, _ index: Int) -> String { "\(itemID)~\(index + 1)" }

    static func placeID(of id: String) -> String {
        id.split(separator: "~", maxSplits: 1).first.map(String.init) ?? id
    }

    /// This item again, standing at one of its branches, for the map only.
    func atBranch(_ index: Int) -> TripItem? {
        guard let branch = branches?[safe: index] else { return nil }
        return TripItem(
            id: Self.branchID(id, index), url: url, name: name, type: type, priority: priority,
            status: status, legCity: legCity, venue: venue, notes: notes, date: date, dateEnd: dateEnd,
            assignedToDate: assignedToDate, assignedToDateEnd: assignedToDateEnd, timeText: timeText,
            address: branch.address, confirmationNumber: confirmationNumber, bookedVia: bookedVia,
            reservationRequired: reservationRequired, reservationMade: reservationMade,
            tripRelationID: tripRelationID, latitude: branch.latitude, longitude: branch.longitude
        )
    }

    /// Every pin this item puts on the map: its own, then one per branch.
    var mapAnnotations: [TripItemAnnotation] {
        guard let latitude, let longitude else { return [] }
        let main = TripItemAnnotation(item: self, coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
        let extra = (branches ?? []).indices.compactMap { index -> TripItemAnnotation? in
            guard let copy = atBranch(index), let lat = copy.latitude, let lon = copy.longitude else { return nil }
            return TripItemAnnotation(item: copy, coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon))
        }
        return [main] + extra
    }

    /// What to show under the name once you are standing there.
    var confirmationLine: String? {
        let parts = [confirmationNumber, bookedVia].filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " - ")
    }

    var displayDate: String? { assignedToDate ?? date }
    var displayDateEnd: String? { assignedToDateEnd ?? dateEnd }

    var displayDateParsed: Date? {
        guard let str = displayDate else { return nil }
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.date(from: str)
    }


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

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
