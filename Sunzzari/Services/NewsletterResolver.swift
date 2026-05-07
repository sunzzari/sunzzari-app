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
}
