import Foundation

/// Picks the prose to render for a `DayBundle`. Prefers a Notion Trip
/// Newsletters entry for the same date; returns nil when none exists, in
/// which case `NewsletterDayCard` falls back to `DayNarrativeService`.
///
/// This is the iOS half of "Phase B" -- newsletters are written by
/// /notion-edit-newsletters into the Notion DB; the iOS app pulls them
/// here and renders them as the day's body. The local generator stays in
/// place for days that have no Notion entry yet.
enum NewsletterResolver {
    static func prose(for day: DayBundle, in newsletters: [String: TripNewsletter]) -> String? {
        guard let n = newsletters[day.dateString], !n.prose.isEmpty else { return nil }
        return n.prose
    }

    /// Pool items the newsletter card actually renders for this day. Dedupes
    /// against `day.confirmed` (by id and lowercased name); when Notion prose
    /// exists, narrows further to pool items whose name appears in that prose.
    /// When there is no Notion prose, all deduped possibilities pass through
    /// (matching the local-narrative fallback in `DayNarrativeService`).
    static func poolDisplayItems(for day: DayBundle, prose: String?) -> [TripItem] {
        let confirmedNames = Set(day.confirmed.map { $0.name.lowercased() })
        let confirmedIDs = Set(day.confirmed.map(\.id))
        let basePool = day.possibilities.filter { item in
            !confirmedIDs.contains(item.id) &&
            !confirmedNames.contains(item.name.lowercased())
        }
        guard let p = prose, !p.isEmpty else { return basePool }
        return basePool.filter { item in
            !item.name.isEmpty && p.localizedCaseInsensitiveContains(item.name)
        }
    }

    static func poolDisplayItems(for day: DayBundle, in newsletters: [String: TripNewsletter]) -> [TripItem] {
        poolDisplayItems(for: day, prose: prose(for: day, in: newsletters))
    }

    /// Full set of items the newsletter card displays for this day: confirmed
    /// anchors plus the filtered pool. The Day-mode map subsets to this so the
    /// map and the prose card show the same universe.
    static func displayItems(for day: DayBundle, in newsletters: [String: TripNewsletter]) -> [TripItem] {
        day.confirmed + poolDisplayItems(for: day, in: newsletters)
    }
}
