import Foundation

/// Period prediction shared by CycleView and the Home summary row.
/// Lifted verbatim out of CycleView so the two surfaces can never disagree
/// about a date.
enum CyclePrediction {

    private static let cal = Calendar(identifier: .gregorian)

    /// How many recent cycles to average over once history exists
    static let avgWindow = 6

    static func defaultAvgCycle(for person: CycleEntry.Person) -> Int {
        switch person {
        case .elisa: return 28
        case .cathy: return 30
        }
    }

    static func latestEntry(in entries: [CycleEntry], for person: CycleEntry.Person) -> CycleEntry? {
        entries.first(where: { $0.person == person })
    }

    /// Computed from the gaps between recent period starts, not the per-entry stored
    /// value — the stored field goes stale the moment a new period is logged.
    static func averageCycle(in entries: [CycleEntry], for person: CycleEntry.Person) -> Int {
        let history = entries
            .filter { $0.person == person }
            .sorted { $0.periodStart > $1.periodStart }

        guard history.count >= 2 else { return defaultAvgCycle(for: person) }

        let recent = Array(history.prefix(avgWindow + 1))
        var gaps: [Int] = []
        for i in 0..<(recent.count - 1) {
            let newer = recent[i].periodStart
            let older = recent[i + 1].periodStart
            if let days = cal.dateComponents([.day], from: older, to: newer).day, days > 0 {
                gaps.append(days)
            }
        }
        guard !gaps.isEmpty else { return defaultAvgCycle(for: person) }
        return Int((Double(gaps.reduce(0, +)) / Double(gaps.count)).rounded())
    }

    static func predictedNext(in entries: [CycleEntry], for person: CycleEntry.Person) -> Date? {
        guard let latest = latestEntry(in: entries, for: person) else { return nil }
        return cal.date(byAdding: .day, value: averageCycle(in: entries, for: person), to: latest.periodStart)
    }

    /// Whole days from today to the predicted date. Negative once it is overdue.
    static func daysUntil(_ date: Date) -> Int {
        cal.dateComponents([.day], from: cal.startOfDay(for: Date()), to: cal.startOfDay(for: date)).day ?? 0
    }
}
