import Foundation

/// Generates a 1-2 sentence narrative intro for a `DayBundle`.
///
/// Pure functions on the bundle. No Notion calls, no Claude. Heuristics fire
/// in priority order: travel day, hotel changeover, beach/outdoor, foodie-
/// anchored, single-anchor, possibility-only, generic fallback. Returns nil
/// when the day has no content (caller hides the card).
///
/// All output is plain text. No emojis, no em-dashes. Sentences end with a
/// period.
enum DayNarrativeService {

    static func narrative(for day: DayBundle) -> String? {
        if day.confirmed.isEmpty && day.possibilities.isEmpty {
            return nil
        }

        let weekday = weekdayName(for: day.date)
        let leg = primaryLeg(for: day)

        // Priority 1: travel day (any transit type confirmed).
        if let travel = travelLine(weekday: weekday, day: day) {
            return travel
        }

        // Priority 2: hotel check-in (a hotel item dated to today).
        if let hotelLine = hotelChangeoverLine(weekday: weekday, day: day) {
            return hotelLine
        }

        // Priority 3: beach / outdoor anchor.
        if let outdoor = outdoorLine(weekday: weekday, leg: leg, day: day) {
            return outdoor
        }

        // Priority 4: foodie-anchored day (2+ restaurants, no activity).
        if let foodie = foodieLine(weekday: weekday, day: day) {
            return foodie
        }

        // Priority 5: single confirmed anchor.
        if day.confirmed.count == 1, let solo = day.confirmed.first {
            let timePart = formattedTime(for: solo)
            if let timeStr = timePart {
                return "\(weekday)'s anchor is \(solo.name) at \(timeStr)."
            }
            return "\(weekday)'s anchor is \(solo.name)."
        }

        // Priority 6: possibility-only day.
        if day.confirmed.isEmpty && !day.possibilities.isEmpty {
            return "\(weekday) is open. A few candidates if you want to fill it."
        }

        // Generic fallback.
        if !leg.isEmpty {
            return "\(weekday) in \(leg)."
        }
        return "\(weekday) on the trip."
    }

    // MARK: - Heuristic helpers

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
