import Foundation

/// Groups a trip's items into days and plans each one.
///
/// Swift twin of the travel-map web app's `lib/day.ts`. Both surfaces must
/// produce the same day for the same data, so changes here need the same
/// change there.
enum TripDayPlanner {

    /// Statuses that put an item on the day's timeline rather than in the
    /// "if you have time" pool.
    static let scheduledStatuses: Set<TripItem.ItemStatus> = [.confirmed, .assigned, .reservationPending]

    struct PlannedItem: Identifiable {
        let item: TripItem
        let time: TripTime
        var id: String { item.id }
    }

    struct DayPlan: Identifiable {
        let dateString: String
        /// 1-based position in the trip, for "Day 3 of 4".
        let dayNumber: Int
        let totalDays: Int
        let legCity: String
        /// Scheduled items in time order, all-day pinned first.
        let timeline: [PlannedItem]
        /// Scheduled items with no usable time.
        let anytime: [PlannedItem]
        /// Shortlisted / Researching: candidates, not commitments.
        let options: [TripItem]
        /// The hotel covering this night, if one is booked.
        let hotel: TripItem?
        /// Needs action: reservation required and not made, or still pending.
        let needsBooking: [TripItem]

        var id: String { dateString }
        var isEmpty: Bool { timeline.isEmpty && anytime.isEmpty }
        var scheduled: [PlannedItem] { timeline + anytime }
    }

    // MARK: - Day grouping

    private static func typeOrder(_ item: TripItem) -> Int { item.type?.sortOrder ?? 99 }

    private static func itemSort(_ a: TripItem, _ b: TripItem) -> Bool {
        let ta = typeOrder(a), tb = typeOrder(b)
        if ta != tb { return ta < tb }
        return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
    }

    /// Date-only portion of a Notion date, which may or may not carry a time.
    private static func dayKey(_ iso: String?) -> String? {
        guard let iso, iso.count >= 10 else { return nil }
        return String(iso.prefix(10))
    }

    private static func addDays(_ dateString: String, _ days: Int) -> String? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = cal.timeZone
        guard let date = fmt.date(from: dateString),
              let next = cal.date(byAdding: .day, value: days, to: date) else { return nil }
        return fmt.string(from: next)
    }

    /// Every date an item occupies. A hotel with a checkout date occupies each
    /// night in between, so "sleeping tonight" is answerable on every day.
    private static func expandedDates(_ item: TripItem) -> [String] {
        guard let start = dayKey(item.displayDate) else { return [] }
        guard item.type == .hotel, let end = dayKey(item.displayDateEnd), end > start else { return [start] }

        var dates: [String] = []
        var cursor = start
        while cursor < end, dates.count < 400 {
            dates.append(cursor)
            guard let next = addDays(cursor, 1) else { break }
            cursor = next
        }
        return dates.isEmpty ? [start] : dates
    }

    // MARK: - Planning

    /// Builds one plan per day of the trip, in date order.
    static func plans(for items: [TripItem]) -> [DayPlan] {
        var byDate: [String: [TripItem]] = [:]
        var legCitiesByDate: [String: Set<String>] = [:]

        let live = items.filter { $0.status != nil && $0.status != .cancelled }

        for item in live {
            for date in expandedDates(item) {
                byDate[date, default: []].append(item)
                if !item.legCity.isEmpty { legCitiesByDate[date, default: []].insert(item.legCity) }
            }
        }

        // Undated candidates surface on every day of the leg they belong to,
        // so "what else is around" is answerable without a date on the item.
        let undated = live.filter {
            dayKey($0.displayDate) == nil && $0.status != .confirmed && !$0.legCity.isEmpty
        }
        for (date, cities) in legCitiesByDate {
            for item in undated where cities.contains(item.legCity) {
                if !(byDate[date]?.contains { $0.id == item.id } ?? false) {
                    byDate[date, default: []].append(item)
                }
            }
        }

        let dates = byDate.keys.sorted()

        return dates.enumerated().map { index, date in
            let dayItems = byDate[date] ?? []

            let scheduled = dayItems.filter { item in
                guard let status = item.status else { return false }
                return scheduledStatuses.contains(status)
            }
            let planned = scheduled.map { PlannedItem(item: $0, time: TripTime.parse(timeText: $0.timeText, isoDate: $0.displayDate)) }

            let scheduledIDs = Set(scheduled.map(\.id))
            let options = dayItems
                .filter { !scheduledIDs.contains($0.id) }
                .filter { $0.status == .shortlisted || $0.status == .researching }
                .sorted(by: itemSort)

            return DayPlan(
                dateString: date,
                dayNumber: index + 1,
                totalDays: dates.count,
                legCity: scheduled.first?.legCity ?? dayItems.first?.legCity ?? "",
                timeline: planned.filter { !$0.time.anytime }.sorted { $0.time.sortKey < $1.time.sortKey },
                anytime: planned.filter { $0.time.anytime }.sorted { itemSort($0.item, $1.item) },
                options: options,
                hotel: scheduled.first { $0.type == .hotel },
                needsBooking: scheduled.filter(needsBooking)
            )
        }
    }

    /// Does this still need booking?
    ///
    /// ONLY `.reservationPending`. That is the single status meaning "she has
    /// said she wants this and it is not booked yet".
    ///
    /// The old rule also counted `reservationRequired && !reservationMade`,
    /// which was the bug Elisa hit on 2026-09-06: `Reservation Required` is
    /// INFERRED by the add-to-trip skill from the item type, so every
    /// restaurant Claude had ever suggested appeared under "Still needs
    /// booking". Her words: "you tell me 'still needs booking' for many things
    /// that i never say im going to book. you just recommend them but i never
    /// actually say i will do it. it makes everything so messy."
    ///
    /// A recommendation is not a commitment. Nothing Claude inferred may put
    /// an item in this list.
    static func needsBooking(_ item: TripItem) -> Bool {
        item.status == .reservationPending
    }

    // MARK: - Which day to open on

    /// Today as yyyy-MM-dd in the DEVICE's timezone.
    static var todayString: String { today(in: nil) }

    /// Today as yyyy-MM-dd in the TRIP's timezone.
    ///
    /// Elisa, 2026-09-06: "the dimming should always happen at the timezone of
    /// the trip". The device is not a safe proxy - checking the plan from LA
    /// the night before a flight, or on a phone that has not switched over
    /// yet, both give the wrong day and would dim a day that has not happened.
    ///
    /// A blank or unrecognised zone falls back to the device, which is the old
    /// behaviour and correct for a trip with no zone recorded.
    static func today(in timeZoneID: String?) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        if let id = timeZoneID, !id.isEmpty, let tz = TimeZone(identifier: id) {
            fmt.timeZone = tz
        }
        return fmt.string(from: Date())
    }

    /// Is this day finished, in the trip's timezone?
    ///
    /// Only a Confirmed item on a finished day counts as done - Elisa,
    /// 2026-09-06: "only dim what we have certainly already done (confirmed)".
    /// Assigned and Shortlisted are intentions, and a plan is not evidence it
    /// happened. Multi-night hotels are expanded per night, so last night dims
    /// while tonight does not, with no special case.
    static func isDone(dayString: String, status: TripItem.ItemStatus?, today: String) -> Bool {
        status == .confirmed && dayString < today
    }

    /// The day to open on: today if the trip covers it, else the next day of
    /// the trip, else the last.
    ///
    /// DATE-BASED ON PURPOSE. Trip Status is not usable for this: on
    /// 2026-09-06, mid-way through Park City (Sep 4-7), that trip's Notion
    /// Trip Status still read "Planning". Nothing flips it to "In Progress".
    static func openingIndex(in plans: [DayPlan], timeZoneID: String? = nil) -> Int {
        guard !plans.isEmpty else { return 0 }
        let today = today(in: timeZoneID)
        if let exact = plans.firstIndex(where: { $0.dateString == today }) { return exact }
        if let upcoming = plans.firstIndex(where: { $0.dateString > today }) { return upcoming }
        return plans.count - 1
    }
}

extension Trip {
    /// True while the trip is running, by date. See `openingIndex` for why
    /// this cannot key off `status`.
    var isLiveToday: Bool {
        guard status != .completed, status != .cancelled, let start = departureDate else { return false }
        // Judged in the TRIP's zone: "am I on this trip today" is a question
        // about where the trip is, not where the phone is.
        let today = TripDayPlanner.today(in: timeZoneID)
        return start <= today && (returnDate ?? start) >= today
    }

    var hasNotStarted: Bool {
        guard status != .completed, status != .cancelled, let start = departureDate else { return false }
        return start > TripDayPlanner.today(in: timeZoneID)
    }
}
