import Foundation

/// Trip item time parsing.
///
/// The Notion `Time` property is deliberately free text: real trips carry a mix
/// of specific times ("9:30am", "19:00") and rough ones ("morning", "evening"),
/// and most items carry nothing at all.
///
/// The rule that matters: a rough word is DISPLAYED AS THE WORD. It is never
/// rendered as the clock time we anchored it to, because that would be a
/// precision nobody entered.
///
/// This is the Swift twin of the travel-map web app's `lib/time.ts`. The bucket
/// table and its anchors must stay identical in both, or the phone and the
/// laptop will order the same day differently.
struct TripTime {
    /// Minutes since midnight, for ordering.
    let sortKey: Int
    /// What to show. Nil means show nothing and group under "Anytime".
    let label: String?
    /// True only when a real clock time was given.
    let exact: Bool
    /// True when the item belongs in the "Anytime" group, not the timeline.
    let anytime: Bool

    /// Sorts above every real time, for items that run the whole day.
    static let allDay = -1
    /// Sorts below every real time.
    static let noTime = 100_000

    static let empty = TripTime(sortKey: noTime, label: nil, exact: false, anytime: true)
}

extension TripTime {

    // Rough time words and the minute they anchor to.
    //
    // Matched LONGEST PHRASE FIRST (see `buckets` below), which is structural
    // rather than a property of how this list happens to be ordered. Substring
    // collisions are everywhere: "afternoon" contains "noon", "late night"
    // contains "night", "early morning" contains "morning".
    private static let rawBuckets: [(String, Int)] = [
        ("all day", allDay),
        ("allday", allDay),
        ("full day", allDay),
        ("first thing", 6 * 60),
        ("sunrise", 6 * 60),
        ("dawn", 6 * 60),
        ("early morning", 7 * 60),
        ("breakfast", 8 * 60),
        ("late morning", 10 * 60 + 30),
        ("morning", 9 * 60),
        ("midday", 12 * 60 + 30),
        ("noon", 12 * 60),
        ("lunch", 12 * 60 + 30),
        ("late afternoon", 16 * 60 + 30),
        ("early afternoon", 13 * 60 + 30),
        ("afternoon", 15 * 60),
        ("golden hour", 18 * 60 + 30),
        ("sunset", 18 * 60 + 30),
        ("aperitivo", 18 * 60 + 30),
        ("apero", 18 * 60 + 30),
        ("drinks", 18 * 60 + 30),
        ("dinner", 19 * 60 + 30),
        ("evening", 19 * 60 + 30),
        ("late night", 22 * 60 + 30),
        ("night", 21 * 60 + 30),
        ("nightcap", 22 * 60),
    ]

    private static let buckets: [(String, Int)] =
        rawBuckets.sorted { $0.0.count > $1.0.count }

    /// Words that explicitly say "there is no time", as opposed to a blank.
    private static let noTimeWords: Set<String> = ["anytime", "any time", "tbd", "flexible"]

    /// "9:30am", "9:30 AM", "19:00", "6:35p", "9am" -> minutes since midnight.
    private static func parseClock(_ raw: String) -> Int? {
        let text = raw.replacingOccurrences(of: " ", with: "").lowercased()
        guard !text.isEmpty else { return nil }

        var digits = ""
        var index = text.startIndex
        while index < text.endIndex, text[index].isNumber {
            digits.append(text[index])
            index = text.index(after: index)
        }
        guard !digits.isEmpty, digits.count <= 2, var hour = Int(digits) else { return nil }

        var minute = 0
        var hasMinutes = false
        if index < text.endIndex, text[index] == ":" {
            index = text.index(after: index)
            var minuteDigits = ""
            while index < text.endIndex, text[index].isNumber {
                minuteDigits.append(text[index])
                index = text.index(after: index)
            }
            guard minuteDigits.count == 2, let m = Int(minuteDigits), m < 60 else { return nil }
            minute = m
            hasMinutes = true
        }

        let suffix = String(text[index...])
        if suffix == "am" || suffix == "a" || suffix == "pm" || suffix == "p" {
            guard (1...12).contains(hour) else { return nil }
            let isPM = suffix.hasPrefix("p")
            if hour == 12 { hour = isPM ? 12 : 0 } else if isPM { hour += 12 }
        } else if suffix.isEmpty {
            // No am/pm marker. A bare 1-2 digit number is a date fragment as
            // often as a time, so require a colon.
            guard hasMinutes, hour <= 23 else { return nil }
        } else {
            return nil
        }

        return hour * 60 + minute
    }

    private static func formatClock(_ minutes: Int) -> String {
        let hour24 = (minutes / 60) % 24
        let minute = minutes % 60
        let suffix = hour24 < 12 ? "AM" : "PM"
        let hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12
        return String(format: "%d:%02d %@", hour12, minute, suffix)
    }

    private static func titleCased(_ text: String) -> String {
        guard let first = text.first else { return text }
        return String(first).uppercased() + text.dropFirst()
    }

    /// - Parameters:
    ///   - timeText: the Notion `Time` property, free text.
    ///   - isoDate: `Assigned to Date` or `Date`, used only if it carries a time.
    static func parse(timeText: String?, isoDate: String? = nil) -> TripTime {
        let raw = (timeText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        if !raw.isEmpty {
            let lower = raw.lowercased()

            if noTimeWords.contains(lower) { return .empty }

            // A clock time, possibly a range ("7:30pm-9pm"): the start orders it.
            let start = lower
                .components(separatedBy: CharacterSet(charactersIn: "-–—"))
                .first?
                .replacingOccurrences(of: " to ", with: "|")
                .replacingOccurrences(of: " until ", with: "|")
                .components(separatedBy: "|").first?
                .trimmingCharacters(in: .whitespaces) ?? lower

            if let clock = parseClock(start) {
                // Show what she typed, so "7:30pm-9pm" keeps its range instead
                // of being flattened to the start.
                return TripTime(sortKey: clock, label: raw, exact: true, anytime: false)
            }

            for (word, anchor) in buckets where lower.contains(word) {
                return TripTime(sortKey: anchor, label: titleCased(raw), exact: false, anytime: false)
            }

            // Unrecognized, but she wrote something. Show her words verbatim; we
            // have no basis to place it on the timeline, so it groups under
            // Anytime rather than being sorted somewhere invented.
            return TripTime(sortKey: noTime, label: titleCased(raw), exact: false, anytime: true)
        }

        // No Time property. Fall back to a time component on the date field,
        // which nothing carries today but which the schema allows.
        if let isoDate, isoDate.contains("T") {
            let timePart = isoDate.components(separatedBy: "T").dropFirst().first ?? ""
            let parts = timePart.prefix(5).components(separatedBy: ":")
            if parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]), h < 24, m < 60 {
                let minutes = h * 60 + m
                return TripTime(sortKey: minutes, label: formatClock(minutes), exact: true, anytime: false)
            }
        }

        return .empty
    }
}
