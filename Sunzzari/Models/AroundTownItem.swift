import Foundation
import CoreLocation
import SwiftUI

/// One LA or SF Bay place on the Around Town map.
///
/// Built from the travel map server's answer (`AroundTownService`), never from
/// Notion rows. Where the place is, which area it belongs to, its colour and its
/// chain branches are all decided on the server by the same code that draws the
/// website, so the two maps cannot disagree. This type only holds the answer
/// and adapts it to the shared map.
struct AroundTownItem: Identifiable {
    enum Kind { case restaurant, activity }

    enum Region {
        case la, sfBay

        init?(server value: String?) {
            switch value {
            case "la": self = .la
            case "sfBay": self = .sfBay
            default: return nil
            }
        }

        var label: String {
            switch self { case .la: return "LA"; case .sfBay: return "SF Bay" }
        }
    }

    /// Another branch of a chain. Drawn as its own pin; a tap opens this place.
    struct Branch {
        let address: String
        let coordinate: CLLocationCoordinate2D
        /// Same meaning as the place's own `fitArea`, decided by the server.
        let fitArea: Region?
    }

    let id: String
    let name: String
    let kind: Kind
    let region: Region?
    /// The "fit all" frame this pin belongs to (LA proper, or the Bay). Nil for
    /// a pin that stays on the map but never stretches the frame, such as
    /// San Diego. Elisa, 2026-09-15: "i only want LA proper. not even orange county".
    let fitArea: Region?
    let subtitle: String       // neighborhood (restaurant) or location text (activity)
    let neighborhood: String
    let locationText: String   // raw Notion Location value
    var thinkingAbout: Bool
    var done: Bool             // beenThere for restaurants, done? for activities
    /// The colour when not yet visited. Been-there grey is applied in `pinStyle`.
    let markerColorHex: String
    let glyph: String          // SF Symbol name
    let preferenceLabel: String?
    let goodFor: [String]
    let topDishes: String
    let comments: String
    let address: String
    let coordinate: CLLocationCoordinate2D?
    let branches: [Branch]

    /// Legend swatches. Pin colours themselves come from the server.
    static let notRatedHex = "#E2E8F0"
    static let activityHex = "#A78BFA"

    init(place p: AroundTownService.Place) {
        let isRestaurant = p.kind == "restaurant"
        id = p.id
        name = p.name
        kind = isRestaurant ? .restaurant : .activity
        region = Region(server: p.region)
        fitArea = Region(server: p.fitArea)
        subtitle = isRestaurant ? (p.neighborhood.isEmpty ? p.location : p.neighborhood) : p.location
        neighborhood = p.neighborhood
        locationText = p.location
        thinkingAbout = p.wantToTry
        done = p.beenThere
        markerColorHex = p.baseColor
        glyph = isRestaurant ? "fork.knife" : "figure.walk"
        preferenceLabel = p.preference
        goodFor = p.goodFor
        topDishes = p.topDishes
        comments = p.comments
        address = p.address
        if let lat = p.lat, let lng = p.lng {
            coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lng)
        } else {
            coordinate = nil
        }
        branches = p.branches.map {
            Branch(
                address: $0.address,
                coordinate: CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng),
                fitArea: Region(server: $0.fitArea)
            )
        }
    }

    /// One-line description shown inside the map callout bubble, mirroring the
    /// travel map's title + subtitle callout. Kept short -- MapKit truncates.
    var calloutSubtitle: String {
        var parts: [String] = []
        if let preferenceLabel, !preferenceLabel.isEmpty { parts.append(preferenceLabel) }
        if !subtitle.isEmpty { parts.append(subtitle) }
        if !goodFor.isEmpty { parts.append(goodFor.prefix(2).joined(separator: ", ")) }
        if parts.isEmpty { parts.append(kind == .restaurant ? "Restaurant" : "Activity") }
        if done { parts.append("Been there") }
        return parts.joined(separator: " · ")
    }

    // MARK: - Branch pins

    /// A branch pin's id on the map. The map tells pins apart by id, and every
    /// tap is mapped back to the place with `placeID(of:)`. Same scheme as the
    /// website (`lib/saved-pins.ts`). Notion ids never contain "~".
    static func branchID(_ placeID: String, _ index: Int) -> String { TripItem.branchID(placeID, index) }
    static func placeID(of id: String) -> String { TripItem.placeID(of: id) }
}

// MARK: - Riding on the travel map

extension AroundTownItem {
    /// The travel map's map, cluster picker and unmapped list all speak
    /// `TripItem`. An Around Town place is the same kind of thing -- a name, a
    /// pin, a note -- so it rides on those through this one adapter rather than
    /// a second copy of the map. Three copies of that map is what let the
    /// numbered bubbles stay broken here for months.
    ///
    /// Every date field is nil on purpose. Around Town places are never
    /// assigned to a day, so nothing downstream can grow a day strip.
    var asTripItem: TripItem { tripItem(id: id, address: address, at: coordinate) }

    private func tripItem(id: String, address: String, at coord: CLLocationCoordinate2D?) -> TripItem {
        TripItem(
            id: id,
            url: "https://www.notion.so/\(self.id.replacingOccurrences(of: "-", with: ""))",
            name: name,
            type: kind == .restaurant ? .restaurant : .activity,
            priority: nil,
            // Status drives pin colour on a trip. Around Town colours by
            // preference instead, through `pinStyle`, so this stays empty
            // rather than borrowing a trip word that does not apply.
            status: nil,
            legCity: subtitle,
            venue: "",
            notes: comments,
            date: nil,
            dateEnd: nil,
            assignedToDate: nil,
            assignedToDateEnd: nil,
            timeText: "",
            address: address.isEmpty ? locationText : address,
            confirmationNumber: "",
            bookedVia: "",
            reservationRequired: false,
            reservationMade: false,
            tripRelationID: nil,
            latitude: coord?.latitude,
            longitude: coord?.longitude
        )
    }

    /// Pin colour and glyph for the shared map. Been-there places go grey but
    /// stay legible -- nothing is faded to near-invisible.
    var pinStyle: MapPinStyle {
        done
            ? MapPinStyle(color: Color(uiColor: .systemGray), glyph: glyph, alpha: 0.9)
            : MapPinStyle(color: Color(hex: markerColorHex), glyph: glyph)
    }

    /// Every pin this place puts on the shared map: its own, plus one per chain
    /// branch (Elisa, 2026-09-30: every branch in the area gets a pin). Empty
    /// when the place has no saved location.
    var annotations: [TripItemAnnotation] {
        guard let coordinate else { return [] }
        let main = TripItemAnnotation(item: asTripItem, coordinate: coordinate, subtitleOverride: calloutSubtitle)
        let extra = branches.enumerated().map { index, branch in
            TripItemAnnotation(
                item: tripItem(id: Self.branchID(id, index), address: branch.address, at: branch.coordinate),
                coordinate: branch.coordinate,
                subtitleOverride: calloutSubtitle
            )
        }
        return [main] + extra
    }
}
