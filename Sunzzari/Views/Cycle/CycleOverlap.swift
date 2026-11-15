import Foundation

/// Decides how Apple Health periods merge into the Notion Cycle Tracker for ONE person.
///
/// Elisa, 2026-11-15: "make sure its no days should be overlapping. the app data takes
/// precedence over the notion data. if any days collide, the app data wins".
///
/// - A Notion entry covers its start day plus the next `CyclePrediction.periodLengthDays - 1`
///   days (the same assumed length the calendar draws).
/// - A Health period covers its first through last logged flow day.
/// - If they share any day, the Health period wins: the Notion entry is moved to the Health
///   start date. Any further Notion entries overlapping that same Health period are removed.
/// - A Health period that overlaps nothing is added. Notion entries that overlap no Health
///   period are left alone.
///
/// Pure (Foundation only) so it can be checked without a phone.
enum CycleOverlap {

    struct Span: Equatable {
        let start: Date
        let end: Date   // last day, inclusive
    }

    struct Existing: Equatable {
        let id: String
        let start: Date
    }

    enum Action: Equatable {
        case add(start: Date)
        case keep(id: String)
        case move(id: String, to: Date)
        case remove(id: String)
    }

    static func plan(health: [Span], notion: [Existing], periodLengthDays: Int,
                     calendar cal: Calendar = Calendar(identifier: .gregorian)) -> [Action] {
        var used = Set<String>()
        var actions: [Action] = []

        for period in health.sorted(by: { $0.start < $1.start }) {
            let colliding = notion
                .filter { !used.contains($0.id) }
                .filter { entry in
                    let entryStart = cal.startOfDay(for: entry.start)
                    let entryEnd = cal.date(byAdding: .day, value: periodLengthDays - 1, to: entryStart) ?? entryStart
                    return entryStart <= period.end && entryEnd >= period.start
                }
                // Prefer the entry already on the right day, then the closest one.
                .sorted { a, b in
                    abs(a.start.timeIntervalSince(period.start)) < abs(b.start.timeIntervalSince(period.start))
                }

            guard let winner = colliding.first else {
                actions.append(.add(start: period.start))
                continue
            }
            used.insert(winner.id)
            if cal.isDate(winner.start, inSameDayAs: period.start) {
                actions.append(.keep(id: winner.id))
            } else {
                actions.append(.move(id: winner.id, to: period.start))
            }
            for extra in colliding.dropFirst() {
                used.insert(extra.id)
                actions.append(.remove(id: extra.id))
            }
        }
        return actions
    }
}
