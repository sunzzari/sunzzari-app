import Foundation
import CoreLocation

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
    var geoVenue: String { name }

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
        guard region != nil || (r.location.isEmpty && !r.neighborhood.isEmpty) else { return nil }
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
            region:         region,
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
            coordinate:     nil
        )
    }
}
