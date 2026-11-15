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
    /// A Health start within this many days of an existing entry is the same period.
    private let duplicateWindowDays = 3
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
        /// Every app that has period data in Health, so a wrong source name shows up.
        var sourceNames: [String] = []
    }

    static func person(forSource name: String) -> CycleEntry.Person {
        name.caseInsensitiveCompare(cathySourceName) == .orderedSame ? .cathy : .elisa
    }

    /// Adds every Health period start from the last 12 months that is not already
    /// logged for that person (within 3 days) to Notion. Returns nil if a sync is running.
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
            let starts = periodStarts(in: mine)
            result.foundInHealth[person] = starts.count
            var added = 0

            for start in starts {
                let isDuplicate = known.contains { entry in
                    entry.person == person &&
                    abs(cal.dateComponents([.day], from: cal.startOfDay(for: entry.periodStart), to: start).day ?? 99) <= duplicateWindowDays
                }
                if isDuplicate { continue }

                let avg = CyclePrediction.averageCycle(in: known, for: person)
                let source = person == .cathy ? Self.cathySourceName : "Apple Health"
                let saved = try await NotionService.shared.addCycleEntry(
                    person: person, periodStart: start, avgCycle: avg, notes: "From \(source)"
                )
                known.append(saved)
                known.sort { $0.periodStart > $1.periodStart }
                added += 1
            }
            result.added[person] = added
        }
        return result
    }

    /// First day of each period in `samples`, as local start-of-day, oldest first.
    /// A day counts when it has any flow logged (not "none"). A new period starts when
    /// Health marks the cycle start, or when the previous flow day is over 7 days back.
    private func periodStarts(in samples: [HKCategorySample]) -> [Date] {
        var flowDays: [Date: Bool] = [:]   // day -> marked as a cycle start
        for sample in samples where sample.value != HKCategoryValueMenstrualFlow.none.rawValue {
            let day = cal.startOfDay(for: sample.startDate)
            let markedStart = (sample.metadata?[HKMetadataKeyMenstrualCycleStart] as? Bool) ?? false
            flowDays[day] = (flowDays[day] ?? false) || markedStart
        }

        var starts: [Date] = []
        var previous: Date?
        for day in flowDays.keys.sorted() {
            let gap = previous.flatMap { cal.dateComponents([.day], from: $0, to: day).day } ?? Int.max
            if gap > newPeriodGapDays || (flowDays[day] == true && gap > 1) {
                starts.append(day)
            }
            previous = day
        }
        let today = cal.startOfDay(for: Date())
        return starts.filter { $0 <= today }
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
