import Foundation

/// Multi-paragraph narrative for a `DayBundle`. Each section is optional;
/// `NewsletterDayCard` renders only the non-nil ones, separated by blank lines.
///
/// Emitted entirely as plain text. No emojis, no em-dashes, period-terminated
/// sentences (per Universal Writing Rules).
struct DayNarrative {
    var intro: String?
    var confirmedParagraph: String?
    var possibilitiesParagraph: String?
    var closing: String?

    var isEmpty: Bool {
        intro == nil && confirmedParagraph == nil && possibilitiesParagraph == nil && closing == nil
    }

    /// All non-nil paragraphs joined by double newlines. Used by share-text
    /// export and as a fallback for any flat-string consumer.
    var joined: String {
        [intro, confirmedParagraph, possibilitiesParagraph, closing]
            .compactMap { $0 }
            .joined(separator: "\n\n")
    }
}

/// Generates a narrative for a `DayBundle`. Pure functions, no Notion calls,
/// no Claude. Phase B will replace this with Claude-generated prose stored in
/// Notion; the iOS card never has to know which source the prose came from.
enum DayNarrativeService {

    /// Local-fallback narrative: intentionally minimal. The deterministic
    /// generator can't synthesize a curated plan -- it would just dump every
    /// possibility into prose and produce a wall of text.
    ///
    /// So this returns ONLY the 1-2 sentence theme intro. The real per-day
    /// "newsletter" is Claude-synthesized at /notion-trip-final-sweep time
    /// and stored in the Trip Newsletters Notion DB; iOS reads from there
    /// via NewsletterResolver (Phase B). When no Notion-side newsletter
    /// exists yet, this minimal intro is what shows.
    static func narrative(for day: DayBundle) -> DayNarrative {
        if day.confirmed.isEmpty && day.possibilities.isEmpty {
            return DayNarrative()
        }
        return DayNarrative(intro: introLine(for: day))
    }

    // MARK: - Intro (1-2 sentences -- the day's theme)

    private static func introLine(for day: DayBundle) -> String? {
        let weekday = weekdayName(for: day.date)
        let leg = primaryLeg(for: day)

        if let travel = travelLine(weekday: weekday, day: day) {
            return travel
        }
        if let hotelLine = hotelChangeoverLine(weekday: weekday, day: day) {
            return hotelLine
        }
        if let outdoor = outdoorLine(weekday: weekday, leg: leg, day: day) {
            return outdoor
        }
        if let foodie = foodieLine(weekday: weekday, day: day) {
            return foodie
        }
        if day.confirmed.count == 1, let solo = day.confirmed.first {
            let timePart = formattedTime(for: solo)
            if let timeStr = timePart {
                return "\(weekday)'s anchor is \(solo.name) at \(timeStr)."
            }
            return "\(weekday)'s anchor is \(solo.name)."
        }
        if day.confirmed.isEmpty && !day.possibilities.isEmpty {
            return "\(weekday) is open. A few candidates if you want to fill it."
        }
        if !leg.isEmpty {
            return "\(weekday) in \(leg)."
        }
        return "\(weekday) on the trip."
    }

    private static func travelLine(weekday: String, day: DayBundle) -> String? {
        let transitTypes: Set<TripItem.ItemType> = [.flight, .train, .ferry, .carRental]
        let transit = day.confirmed.filter { item in
            guard let t = item.type else { return false }
            return transitTypes.contains(t)
        }
        guard !transit.isEmpty else { return nil }

        let originLeg = transit.first?.legCity ?? ""
        let destinationLeg = transit.last?.legCity ?? ""
        if !originLeg.isEmpty && !destinationLeg.isEmpty && originLeg != destinationLeg {
            return "\(weekday) is a travel day from \(originLeg) to \(destinationLeg)."
        }
        if let only = transit.first {
            let typeWord = only.type?.rawValue.lowercased() ?? "transit"
            return "\(weekday) is a travel day. \(typeWord.capitalized) to \(only.legCity)."
        }
        return "\(weekday) is a travel day."
    }

    private static func hotelChangeoverLine(weekday: String, day: DayBundle) -> String? {
        let hotels = day.confirmed.filter { $0.type == .hotel }
        guard let hotel = hotels.first(where: { $0.displayDate == day.dateString }) else {
            return nil
        }
        let leg = hotel.legCity.isEmpty ? "" : " in \(hotel.legCity)"
        return "\(weekday) you check in at \(hotel.name)\(leg)."
    }

    private static func outdoorLine(weekday: String, leg: String, day: DayBundle) -> String? {
        let outdoorKeywords = ["beach", "swim", "hike", "trail", "kayak", "cycling", "bike", "snorkel"]
        let allItems = day.confirmed + day.possibilities
        let activityItems = allItems.filter { $0.type == .activity }

        for item in activityItems {
            let blob = (item.name + " " + item.notes).lowercased()
            for kw in outdoorKeywords {
                if blob.contains(kw) {
                    if kw == "beach" || kw == "swim" {
                        let where_ = leg.isEmpty ? "" : " in \(leg)"
                        return "\(weekday) is your beach day\(where_)."
                    }
                    return "\(weekday) is built around \(item.name)."
                }
            }
        }
        return nil
    }

    private static func foodieLine(weekday: String, day: DayBundle) -> String? {
        let restaurants = day.confirmed.filter { $0.type == .restaurant }
        let hasActivity = day.confirmed.contains { $0.type == .activity }
        guard restaurants.count >= 2 && !hasActivity else { return nil }

        let first = restaurants.first?.name ?? ""
        let last = restaurants.last?.name ?? ""
        return "\(weekday) is built around two reservations. Lunch at \(first), dinner at \(last)."
    }

    // MARK: - Confirmed paragraph

    /// Stitch the day's confirmed items into a single sentence (or two).
    /// Skips the case where there's only one confirmed item -- that's covered
    /// by the intro's single-anchor heuristic.
    private static func confirmedParagraph(for day: DayBundle) -> String? {
        let confirmed = day.confirmed
        guard confirmed.count >= 2 else { return nil }

        let phrases = confirmed.map { describeItem($0, includeTime: true, includeVenue: true) }

        if phrases.count == 2 {
            return "Anchored by \(phrases[0]) and \(phrases[1])."
        }
        // 3+: list with serial commas
        let head = phrases.dropLast().joined(separator: ", ")
        let tail = phrases.last ?? ""
        return "You've got \(head), and \(tail)."
    }

    /// Description of an item as a phrase fragment. Includes time prefix when
    /// the displayDate carries time, and "at {venue}" when venue differs from
    /// name. Lowercase first letter so it slots into a sentence cleanly.
    private static func describeItem(_ item: TripItem, includeTime: Bool, includeVenue: Bool) -> String {
        var parts: [String] = []
        if includeTime, let timeStr = formattedTime(for: item) {
            parts.append(timeStr)
        }
        parts.append(item.name)
        if includeVenue && !item.venue.isEmpty && item.venue != item.name {
            parts.append("at \(item.venue)")
        }
        return parts.joined(separator: " ")
    }

    // MARK: - Possibilities paragraph

    /// Stitch the day's possibilities into a sentence with proximity hints.
    private static func possibilitiesParagraph(for day: DayBundle) -> String? {
        let pos = day.possibilities
        guard !pos.isEmpty else { return nil }

        // Build "{name} ({proximity})" fragments. Proximity is dropped when
        // there's no confirmed anchor for the day.
        let fragments: [String] = pos.map { item in
            let proximity = ProximityHelper.proximityLine(for: item, in: day.confirmed)
            if let prox = proximity {
                return "\(item.name) (\(prox))"
            }
            return item.name
        }

        switch fragments.count {
        case 1:
            return "Optional: \(fragments[0])."
        case 2:
            return "You could fit in \(fragments[0]) or \(fragments[1])."
        default:
            // 3+: list with serial commas
            let head = fragments.dropLast().joined(separator: ", ")
            let tail = fragments.last ?? ""
            return "If you've got time, \(head), and \(tail)."
        }
    }

    // MARK: - Closing

    /// Short closing sentence. Surfaces the day's hotel anchor when the hotel
    /// item exists in confirmed/possibilities but wasn't the intro's subject
    /// (i.e. not a check-in day).
    private static func closingLine(for day: DayBundle) -> String? {
        let hotels = (day.confirmed + day.possibilities).filter { $0.type == .hotel }
        guard let hotel = hotels.first else { return nil }
        // If the intro already mentioned this hotel as a check-in, skip.
        if hotel.displayDate == day.dateString { return nil }
        return "Sleeping at \(hotel.name)."
    }

    // MARK: - Formatters

    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE"
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    private static func weekdayName(for date: Date) -> String {
        weekdayFormatter.string(from: date)
    }

    private static func primaryLeg(for day: DayBundle) -> String {
        let allLegs = (day.confirmed + day.possibilities).map(\.legCity).filter { !$0.isEmpty }
        guard !allLegs.isEmpty else { return "" }
        let counts = Dictionary(grouping: allLegs, by: { $0 }).mapValues(\.count)
        return counts.max(by: { $0.value < $1.value })?.key ?? ""
    }

    /// Returns "8 AM" / "7:30 PM" if the item's displayDate carries a time.
    /// Notion date fields can include time when set to "Include time"; the
    /// raw string for those is "yyyy-MM-dd'T'HH:mm:ss.SSSXXX". For pure
    /// date strings (yyyy-MM-dd), returns nil.
    static func formattedTime(for item: TripItem) -> String? {
        guard let str = item.displayDate, str.contains("T") else { return nil }
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoFormatter.date(from: str) {
            return timeFormatter.string(from: date)
        }
        let fallback = ISO8601DateFormatter()
        fallback.formatOptions = [.withInternetDateTime]
        if let date = fallback.date(from: str) {
            return timeFormatter.string(from: date)
        }
        return nil
    }
}
