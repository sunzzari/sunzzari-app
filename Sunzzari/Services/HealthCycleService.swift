import Foundation
import HealthKit

/// Reads period starts from Apple Health on Elisa's phone and adds any missing ones
/// to the shared Notion Cycle Tracker, so Cathy's phone sees them too.
///
/// Who a period belongs to is decided by the app that logged it in Health:
/// - entries logged by the "My Cycle" app are Cathy's (Elisa logs only Cathy there, 2026-11-15)
/// - entries from every other source (Apple Health itself, a watch) are Elisa's
///
/// Apple Health data lives on the phone that logged it, so this only runs on the
/// phone whose identity is Branch (Elisa). Cathy's phone never shows it.
/// Read-only: the app never writes to Apple Health.
@MainActor
final class HealthCycleService {
    static let shared = HealthCycleService()

    private let store = HKHealthStore()
    private let cal = Calendar(identifier: .gregorian)
    private let connectedKey = "sunzzari_health_cycle_connected"
    private var isSyncing = false

    /// Health source name whose entries are Cathy's (matched ignoring case).
    static let cathySourceName = "My Cycle"
    /// How far back each pull looks (Elisa chose 12 months, 2026-11-15).
    private let lookbackMonths = 12
    /// Flow days further apart than this belong to different periods.
    private let newPeriodGapDays = 7

    private init() {}

    /// True only on Elisa's phone, on a device that has Apple Health.
    var isEligible: Bool {
        AppIdentity.current == .branch && HKHealthStore.isHealthDataAvailable()
    }

    var isConnected: Bool {
        get { UserDefaults.standard.bool(forKey: connectedKey) }
        set { UserDefaults.standard.set(newValue, forKey: connectedKey) }
    }

    /// Shows the Apple Health permission sheet (read menstrual flow only).
    func connect() async throws {
        guard isEligible else { return }
        let flow = HKCategoryType(.menstrualFlow)
        try await store.requestAuthorization(toShare: [], read: [flow])
        isConnected = true
    }

    struct SyncResult {
        var foundInHealth: [CycleEntry.Person: Int] = [:]
        var added: [CycleEntry.Person: Int] = [:]
        /// Notion entries moved to the Health date because their days overlapped.
        var corrected: [CycleEntry.Person: Int] = [:]
        /// Extra Notion entries removed (moved to Notion's trash) because a Health period replaced them.
        var removed: [CycleEntry.Person: Int] = [:]
        /// Every app that has period data in Health, so a wrong source name shows up.
        var sourceNames: [String] = []
    }

    static func person(forSource name: String) -> CycleEntry.Person {
        name.caseInsensitiveCompare(cathySourceName) == .orderedSame ? .cathy : .elisa
    }

    /// Merges every Health period from the last 12 months into Notion for each person.
    /// Overlapping days are never kept twice: Health wins (see `CycleOverlap`).
    /// Returns nil if a sync is already running.
    func sync(existing: [CycleEntry]) async throws -> SyncResult? {
        guard isEligible, isConnected, !isSyncing else { return nil }
        isSyncing = true
        defer { isSyncing = false }

        let since = cal.date(byAdding: .month, value: -lookbackMonths, to: Date()) ?? Date()
        let samples = try await flowSamples(since: since)

        var result = SyncResult()
        result.sourceNames = Array(Set(samples.map { $0.sourceRevision.source.name })).sorted()

        var known = existing
        for person in CycleEntry.Person.allCases {
            let mine = samples.filter { Self.person(forSource: $0.sourceRevision.source.name) == person }
            let periods = periodSpans(in: mine)
            result.foundInHealth[person] = periods.count
            let note = "From \(person == .cathy ? Self.cathySourceName : "Apple Health")"

            let actions = CycleOverlap.plan(
                health: periods,
                notion: known.filter { $0.person == person }.map { .init(id: $0.id, start: $0.periodStart) },
                periodLengthDays: CyclePrediction.periodLengthDays,
                calendar: cal
            )
            var added = 0, corrected = 0, removed = 0
            for action in actions {
                switch action {
                case .keep:
                    break
                case .add(let start):
                    let avg = CyclePrediction.averageCycle(in: known, for: person)
                    let saved = try await NotionService.shared.addCycleEntry(
                        person: person, periodStart: start, avgCycle: avg, notes: note)
                    known.append(saved)
                    added += 1
                case .move(let id, let start):
                    try await NotionService.shared.updateCycleEntry(id: id, periodStart: start)
                    if let i = known.firstIndex(where: { $0.id == id }) { known[i].periodStart = start }
                    corrected += 1
                case .remove(let id):
                    try await NotionService.shared.archivePage(id: id)
                    known.removeAll { $0.id == id }
                    removed += 1
                }
                known.sort { $0.periodStart > $1.periodStart }
            }
            result.added[person] = added
            result.corrected[person] = corrected
            result.removed[person] = removed
        }
        return result
    }

    /// Each period in `samples` as first..last flow day (local start-of-day), oldest first.
    /// A day counts when it has any flow logged (not "none"). A new period starts when
    /// Health marks the cycle start, or when the previous flow day is over 7 days back.
    private func periodSpans(in samples: [HKCategorySample]) -> [CycleOverlap.Span] {
        var flowDays: [Date: Bool] = [:]   // day -> marked as a cycle start
        for sample in samples where sample.value != HKCategoryValueMenstrualFlow.none.rawValue {
            let day = cal.startOfDay(for: sample.startDate)
            let markedStart = (sample.metadata?[HKMetadataKeyMenstrualCycleStart] as? Bool) ?? false
            flowDays[day] = (flowDays[day] ?? false) || markedStart
        }

        var spans: [CycleOverlap.Span] = []
        var previous: Date?
        for day in flowDays.keys.sorted() {
            let gap = previous.flatMap { cal.dateComponents([.day], from: $0, to: day).day } ?? Int.max
            if gap > newPeriodGapDays || (flowDays[day] == true && gap > 1) {
                spans.append(.init(start: day, end: day))
            } else if let last = spans.last {
                spans[spans.count - 1] = .init(start: last.start, end: day)
            }
            previous = day
        }
        let today = cal.startOfDay(for: Date())
        return spans.filter { $0.start <= today }
    }

    private func flowSamples(since: Date) async throws -> [HKCategorySample] {
        let type = HKCategoryType(.menstrualFlow)
        let predicate = HKQuery.predicateForSamples(withStart: since, end: Date(), options: [])
        return try await withCheckedThrowingContinuation { cont in
            let query = HKSampleQuery(
                sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, results, error in
                if let error { cont.resume(throwing: error); return }
                cont.resume(returning: (results as? [HKCategorySample]) ?? [])
            }
            store.execute(query)
        }
    }
}
