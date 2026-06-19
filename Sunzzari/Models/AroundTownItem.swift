import Foundation
import CoreLocation

struct AroundTownItem: Identifiable {
    enum Kind { case restaurant, activity }
    enum Region { case la, sfBay }

    let id: String
    let name: String
    let kind: Kind
    let region: Region?
    let subtitle: String       // neighborhood (restaurant) or location text (activity)
    var thinkingAbout: Bool
    var done: Bool             // beenThere for restaurants, done? for activities
    let markerColorHex: String
    let glyph: String          // SF Symbol name
    var coordinate: CLLocationCoordinate2D?

    // Stable geo cache key shared with the existing restaurant geo cache
    static func geoKey(for id: String) -> String { "sunzzari_around_geo_\(id)" }
}

// MARK: - Region classification helpers

extension AroundTownItem.Region {
    static func from(location: String) -> AroundTownItem.Region? {
        let loc = location.lowercased()
        let laTokens  = ["la", "oc", "san diego", "los angeles", "orange county", "silverlake",
                         "venice", "santa monica", "pasadena", "culver city", "west hollywood",
                         "los feliz", "echo park", "koreatown"]
        let sfTokens  = ["sf", "east bay", "marin", "napa", "san francisco", "oakland",
                         "berkeley", "sausalito", "mill valley", "sonoma"]
        let isLA = laTokens.contains { loc.contains($0) }
        let isSF = sfTokens.contains { loc.contains($0) }
        if isLA && isSF { return .la } // "LA / SF" → show in both, default to la region key
        if isLA { return .la }
        if isSF { return .sfBay }
        return nil
    }

    var label: String {
        switch self { case .la: return "LA"; case .sfBay: return "SF Bay" }
    }
}

// MARK: - Build from domain models

extension AroundTownItem {
    static func from(_ r: Restaurant) -> AroundTownItem? {
        let region = Region.from(location: r.location)
        // Include only home locations (LA / SF Bay region recognised)
        guard region != nil || r.location.lowercased().contains("la / sf") else { return nil }
        let color: String
        switch r.preference {
        case .topChoice: color = "#54A0FF"
        case .great:     color = "#70C17C"
        case .good:      color = "#FBBF24"
        case .bad:       color = "#FF6B6B"
        case nil:        color = "#8E8E93"
        }
        return AroundTownItem(
            id:            r.id,
            name:          r.name,
            kind:          .restaurant,
            region:        region,
            subtitle:      r.neighborhood.isEmpty ? r.location : r.neighborhood,
            thinkingAbout: r.thinkingAbout,
            done:          r.beenThere,
            markerColorHex: color,
            glyph:         "fork.knife",
            coordinate:    nil
        )
    }

    static func from(_ a: Activity) -> AroundTownItem? {
        guard a.home else { return nil }
        let region = Region.from(location: a.location)
        return AroundTownItem(
            id:            a.id,
            name:          a.name,
            kind:          .activity,
            region:        region,
            subtitle:      a.location,
            thinkingAbout: a.thinkingAbout,
            done:          a.done,
            markerColorHex: "#A78BFA",
            glyph:         "figure.walk",
            coordinate:    nil
        )
    }
}
