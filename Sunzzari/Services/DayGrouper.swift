import Foundation

enum DayGrouper {

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    static func group(items: [TripItem], trip: Trip? = nil) -> [DayBundle] {
        var confirmedByDate: [String: [TripItem]] = [:]
        var possibilitiesByDate: [String: [TripItem]] = [:]
        // Per-day set of legCities, derived from items WITH dates. Used to
        // decide which dateless leg-matched items show as possibilities below.
        var legCitiesByDate: [String: Set<String>] = [:]

        for item in items {
            guard let status = item.status, status != .cancelled else { continue }

            let dates = expandedDates(for: item)
            guard !dates.isEmpty else { continue }

            for d in dates {
                if !item.legCity.isEmpty { legCitiesByDate[d, default: []].insert(item.legCity) }
            }

            switch status {
            case .confirmed:
                for d in dates { confirmedByDate[d, default: []].append(item) }
            case .assigned, .shortlisted, .researching, .reservationPending:
                for d in dates { possibilitiesByDate[d, default: []].append(item) }
            case .cancelled:
                break
            }
        }

        // Surface dateless possibilities into every day whose legCity matches.
        // This is the morning-of-trip "what could I fit in today?" list -- shortlisted
        // and researching items the user could pick up that day, even if they never
        // assigned a specific date. Scoped by legCity so Sardinia options don't show
        // on Paris days.
        let datelessPossibilities = items.filter { item in
            guard let status = item.status, status != .cancelled, status != .confirmed else { return false }
            return item.displayDate == nil && !item.legCity.isEmpty
        }
        for (dateStr, cities) in legCitiesByDate {
            for item in datelessPossibilities where cities.contains(item.legCity) {
                possibilitiesByDate[dateStr, default: []].append(item)
            }
        }

        let allDates = Set(confirmedByDate.keys).union(possibilitiesByDate.keys).sorted()

        return allDates.compactMap { dateStr -> DayBundle? in
            guard let date = formatter.date(from: dateStr) else { return nil }
            let confirmed = (confirmedByDate[dateStr] ?? []).sorted(by: itemSort)
            let possibilities = (possibilitiesByDate[dateStr] ?? []).sorted(by: itemSort)
            guard !confirmed.isEmpty || !possibilities.isEmpty else { return nil }
            return DayBundle(date: date, dateString: dateStr, confirmed: confirmed, possibilities: possibilities)
        }
    }

    /// For multi-night hotels (Hotel type with both start and end dates), expand
    /// to one entry per night in [start, end). Notion checkout dates are exclusive.
    /// All other items return their single displayDate.
    private static func expandedDates(for item: TripItem) -> [String] {
        guard let start = item.displayDate else { return [] }

        if item.type == .hotel,
           let end = item.displayDateEnd,
           let startDate = formatter.date(from: start),
           let endDate = formatter.date(from: end),
           endDate > startDate {
            var dates: [String] = []
            var cursor = startDate
            while cursor < endDate {
                dates.append(formatter.string(from: cursor))
                guard let next = Calendar(identifier: .gregorian).date(byAdding: .day, value: 1, to: cursor) else { break }
                cursor = next
            }
            return dates
        }

        return [start]
    }

    private static func itemSort(_ a: TripItem, _ b: TripItem) -> Bool {
        let ta = a.type?.sortOrder ?? 99
        let tb = b.type?.sortOrder ?? 99
        if ta != tb { return ta < tb }
        return a.name < b.name
    }
}
