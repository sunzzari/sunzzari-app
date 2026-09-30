import Foundation
import CoreLocation
import SwiftUI

struct AroundTownItem: Identifiable {
    enum Kind { case restaurant, activity }
    enum Region { case la, sfBay }

    let id: String
    let name: String
    let kind: Kind
    var region: Region?        // refined from the geocoded coordinate when available
    let subtitle: String       // neighborhood (restaurant) or location text (activity)
    let locationText: String   // raw Notion Location value
    var thinkingAbout: Bool
    var done: Bool             // beenThere for restaurants, done? for activities
    let markerColorHex: String
    let glyph: String          // SF Symbol name
    let preferenceLabel: String?
    let goodFor: [String]
    let topDishes: String
    let comments: String
    /// Street address from Notion. When set it is what gets geocoded.
    let address: String
    var coordinate: CLLocationCoordinate2D?

    // Stable geo cache key shared with the existing restaurant geo cache
    static func geoKey(for id: String) -> String { "sunzzari_around_geo_\(id)" }

    /// A restaurant Elisa has not given a Preference to. Light enough to read as
    /// "no rating yet" and distinct from both the tier colours and the grey used
    /// for places we have already been.
    static let notRatedHex = "#E2E8F0"
    static let activityHex = "#A78BFA"

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

    /// Geocoder inputs, in the venue + city shape the travel map's endpoint takes.
    /// The city hint is what keeps a same-named place in another metro from winning.
    var geoVenue: String { address.isEmpty ? name : address }

    /// Notion's Location select mapped to a real city. Using the coarse metro
    /// instead sent every San Diego and Napa row to Los Angeles / San Francisco,
    /// where the lookup found nothing and fell back to a city centroid.
    private static let cityByLocation: [String: String] = [
        "la": "Los Angeles, CA",
        "sf": "San Francisco, CA",
        "oc": "Orange County, CA",
        "san diego": "San Diego, CA",
        "napa": "Napa, CA",
        "marin": "Marin County, CA",
        "east bay": "Oakland, CA"
    ]

    /// Widest sensible area for the item, used as the last attempt.
    var metroHint: String {
        switch Region.from(location: locationText) {
        case .sfBay: return "San Francisco Bay Area, CA"
        case .la, nil: return "Los Angeles, CA"
        }
    }

    private var locationCity: String {
        let first = locationText
            .split(separator: "/")
            .first
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() } ?? ""
        return Self.cityByLocation[first] ?? metroHint
    }

    /// First attempt. Restaurants get neighborhood plus city; activities carry
    /// their own free-text location ("Malibu, CA", "Getty Center, Los Angeles").
    var geoCity: String {
        guard address.isEmpty else { return "" }
        switch kind {
        case .restaurant:
            let city = locationCity
            return (subtitle.isEmpty || subtitle == locationText) ? city : "\(subtitle), \(city)"
        case .activity:
            return locationText.isEmpty ? metroHint : locationText
        }
    }

    /// Second attempt, without the neighborhood: the three "626" rows and a few
    /// others only resolve once that text is dropped.
    var geoCityFallback: String {
        kind == .restaurant ? locationCity : metroHint
    }
}

// MARK: - Region classification

extension AroundTownItem.Region {
    /// Multi-word place names -- matched as substrings.
    private static let laPhrases = [
        "los angeles", "orange county", "san diego", "santa monica", "culver city",
        "west hollywood", "los feliz", "echo park", "silver lake", "silverlake",
        "highland park", "eagle rock", "little tokyo", "exposition park",
        "universal city", "long beach", "manhattan beach", "hermosa beach",
        "redondo beach", "beverly hills", "san gabriel", "monterey park",
        "el segundo", "playa vista", "marina del rey", "san pedro",
        "sherman oaks", "studio city", "thousand oaks", "santa clarita",
        "newport beach", "laguna beach", "huntington beach", "costa mesa"
    ]
    private static let laWords = [
        "la", "oc", "socal", "hollywood", "venice", "pasadena", "koreatown",
        "chinatown", "brentwood", "westwood", "sawtelle", "malibu", "burbank",
        "glendale", "arcadia", "alhambra", "torrance", "calabasas", "dtla",
        "getty", "yamashiro", "larchmont", "anaheim", "irvine", "fullerton"
    ]
    private static let sfPhrases = [
        "san francisco", "east bay", "mill valley", "walnut creek", "half moon bay",
        "point reyes", "palo alto", "mountain view", "san mateo", "san jose",
        "san rafael", "daly city", "santa cruz", "santa rosa", "russian hill",
        "nob hill", "hayes valley", "north beach", "castro", "sunset district"
    ]
    private static let sfWords = [
        "sf", "bay", "marin", "napa", "sonoma", "oakland", "berkeley", "sausalito",
        "healdsburg", "petaluma", "novato", "tiburon", "alameda", "emeryville",
        "richmond", "presidio", "soma", "mission", "peninsula", "sfo", "yountville",
        "sebastopol", "larkspur", "corte", "burlingame", "menlo"
    ]

    /// Text classification. Short tokens are matched on word boundaries so a
    /// foreign city ("Milan") can never match a two-letter token ("la").
    static func from(location: String) -> AroundTownItem.Region? {
        let loc = location.lowercased()
        guard !loc.isEmpty else { return nil }
        let words = Set(loc.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))

        let isLA = laPhrases.contains { loc.contains($0) } || laWords.contains { words.contains($0) }
        let isSF = sfPhrases.contains { loc.contains($0) } || sfWords.contains { words.contains($0) }

        if isLA && isSF { return .la }  // "LA / SF" -- coordinate decides later
        if isLA { return .la }
        if isSF { return .sfBay }
        return nil
    }

    /// Authoritative classification once a coordinate exists. Also used to reject
    /// bad geocodes: a pin outside both boxes is not an Around Town place.
    static func from(coordinate c: CLLocationCoordinate2D) -> AroundTownItem.Region? {
        if c.latitude >= 32.5 && c.latitude <= 34.9 &&
           c.longitude >= -119.5 && c.longitude <= -116.7 { return .la }
        if c.latitude >= 36.8 && c.latitude <= 38.9 &&
           c.longitude >= -123.3 && c.longitude <= -121.4 { return .sfBay }
        return nil
    }

    /// The area a FIT may span. Deliberately TIGHTER than the area a pin may
    /// belong to. Elisa, 2026-09-15: *"when im on LA in the sunzzari app it also
    /// zooms out to san diego. i only want LA proper. not even orange county."*
    ///
    /// `from(coordinate:)` above stays wide ON PURPOSE - it decides whether a pin
    /// is kept at all, so narrowing it would strip every San Diego and Orange
    /// County place off the map instead of merely leaving it out of the frame.
    /// A place outside this box keeps its pin and stays tappable; it just never
    /// stretches the frame. Same rule as `fitScopeIds` on the trip map.
    ///
    /// LA proper is LA County, coast through the San Gabriel Valley: Long Beach,
    /// San Pedro, Torrance and the beach cities at the south edge; Malibu and
    /// Calabasas west; Santa Clarita at the north edge; Pasadena, Arcadia and
    /// Monterey Park east. Anaheim (-117.91) and Fullerton (-117.92) sit just
    /// outside the eastern edge; Irvine, Newport, Costa Mesa and Huntington
    /// Beach sit below the southern edge. San Diego is nowhere near it.
    func containsForFit(_ c: CLLocationCoordinate2D) -> Bool {
        switch self {
        case .la:
            return c.latitude >= 33.70 && c.latitude <= 34.45 &&
                   c.longitude >= -118.95 && c.longitude <= -117.95
        case .sfBay:
            return Self.from(coordinate: c) == .sfBay
        }
    }

    var label: String {
        switch self { case .la: return "LA"; case .sfBay: return "SF Bay" }
    }
}

// MARK: - Build from domain models

extension AroundTownItem {
    static func from(_ r: Restaurant) -> AroundTownItem? {
        // Every LA / SF Bay restaurant is included -- tried or not. A blank
        // Location with a neighborhood is still a candidate ("Rokusho", blank
        // Location, Neighborhood "Hollywood") -- the coordinate decides, so the
        // row is placed or counted, never silently dropped. A row that resolves
        // to another metro is out of area, which is not the same as unplaceable.
        let region = Region.from(location: r.location)
        // A blank Location is still a candidate IF the NEIGHBOURHOOD reads as
        // LA or the Bay ("Rokusho", blank Location, Neighborhood "Hollywood").
        // Accepting it merely because a neighbourhood exists let 11 rows with a
        // Chengdu or Shanghai neighbourhood in; they never showed because the
        // coordinate box kept them off the map and nothing listed the rows the
        // map could not place. Now that list exists, so the rule is tightened.
        let neighborhoodRegion = r.location.isEmpty
            ? Region.from(location: r.neighborhood)
            : nil
        guard region != nil || neighborhoodRegion != nil else { return nil }
        // Not-rated is its OWN colour. It was briefly Top Choice blue, which put
        // 142 unrated places in the same blue as the 57 actual top choices.
        let color: String
        switch r.preference {
        case .topChoice: color = "#54A0FF"
        case .great:     color = "#70C17C"
        case .good:      color = "#FBBF24"
        case .bad:       color = "#FF6B6B"
        case nil:        color = AroundTownItem.notRatedHex
        }
        return AroundTownItem(
            id:             r.id,
            name:           r.name,
            kind:           .restaurant,
            region:         region ?? neighborhoodRegion,
            subtitle:       r.neighborhood.isEmpty ? r.location : r.neighborhood,
            locationText:   r.location,
            thinkingAbout:  r.thinkingAbout,
            done:           r.beenThere,
            markerColorHex: color,
            glyph:          "fork.knife",
            preferenceLabel: r.preference?.rawValue,
            goodFor:        r.goodFor,
            topDishes:      r.topDishes,
            comments:       r.comments,
            address:        r.address,
            coordinate:     nil
        )
    }

    static func from(_ a: Activity) -> AroundTownItem? {
        // An activity earns a pin when its location places it in LA / SF Bay.
        // A blank location is still a candidate -- the geocode is validated
        // against the LA / SF Bay boxes and the metro centroids first, so
        // "Thatchers Brentwood" lands and "Sushi making" is counted as having no
        // map location instead of disappearing. Requiring `Home?` here was
        // backwards: it is checked on 8 of 39 rows, and those 8 are the
        // unmappable ones, while every real place (Getty, Griffith Park, Malibu,
        // Nintendo World) had it unchecked. A row in another region -- Yosemite,
        // Paso Robles -- is out of area and stays excluded, not counted.
        let region = Region.from(location: a.location)
        guard region != nil || a.location.isEmpty else { return nil }
        return AroundTownItem(
            id:             a.id,
            name:           a.name,
            kind:           .activity,
            region:         region,
            subtitle:       a.location,
            locationText:   a.location,
            thinkingAbout:  a.thinkingAbout,
            done:           a.done,
            markerColorHex: AroundTownItem.activityHex,
            glyph:          "figure.walk",
            preferenceLabel: nil,
            goodFor:        [],
            topDishes:      "",
            comments:       "",
            address:        a.address,
            coordinate:     nil
        )
    }
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
    var asTripItem: TripItem {
        TripItem(
            id: id,
            url: "https://www.notion.so/\(id.replacingOccurrences(of: "-", with: ""))",
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
            latitude: coordinate?.latitude,
            longitude: coordinate?.longitude
        )
    }

    /// Pin colour and glyph for the shared map. Been-there places go grey but
    /// stay legible -- nothing is faded to near-invisible.
    var pinStyle: MapPinStyle {
        done
            ? MapPinStyle(color: Color(uiColor: .systemGray), glyph: glyph, alpha: 0.9)
            : MapPinStyle(color: Color(hex: markerColorHex), glyph: glyph)
    }

    /// Map annotation for the shared map, carrying the Around Town callout line
    /// instead of a trip item's type/leg/status line.
    func annotation(at coord: CLLocationCoordinate2D) -> TripItemAnnotation {
        TripItemAnnotation(item: asTripItem, coordinate: coord, subtitleOverride: calloutSubtitle)
    }
}
