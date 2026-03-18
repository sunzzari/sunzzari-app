import Foundation
import UserNotifications

/// Single source of truth for "which entry to show on a given day."
/// Both TodayView and notifications call selectEntry() — they will always agree.
/// runDailySetup() is called at 12:01am (via midnight trigger) or first foreground of the day.
final class DailySetupService: @unchecked Sendable {
    static let shared = DailySetupService()
    private init() {}

    private static let pickPrefix      = "sunzzari_today_"
    private static let setupDonePrefix = "sunzzari_setup_done_"

    // MARK: - Entry selection

    /// Picks the single entry to represent a given day. Persists pick in UserDefaults so
    /// repeated calls for the same day always return the same entry.
    ///
    /// Tier 1: Best Moments matching month/day
    /// Tier 2: Other category (not bestMoments, not improvements) matching month/day
    /// Tier 3: Unassigned (isYearOnly, not improvements) — random, persisted
    func selectEntry(for date: Date, from entries: [BestOfEntry]) -> BestOfEntry? {
        let cal   = Calendar(identifier: .gregorian)
        let month = cal.component(.month, from: date)
        let day   = cal.component(.day, from: date)
        let udKey = "\(Self.pickPrefix)\(dateString(for: date))"

        // Tier 1
        if let tier1 = entries.first(where: {
            $0.category == .bestMoments && !$0.isYearOnly &&
            cal.component(.month, from: $0.date) == month &&
            cal.component(.day,   from: $0.date) == day
        }) { return tier1 }

        // Tier 2
        if let tier2 = entries.first(where: {
            $0.category != .bestMoments && $0.category != .improvements && !$0.isYearOnly &&
            cal.component(.month, from: $0.date) == month &&
            cal.component(.day,   from: $0.date) == day
        }) { return tier2 }

        // Tier 3: unassigned pool — read or pick-and-persist
        let pool = entries.filter { $0.isYearOnly && $0.category != .improvements }
        guard !pool.isEmpty else { return nil }

        if let savedID = UserDefaults.standard.string(forKey: udKey),
           let saved = pool.first(where: { $0.id == savedID }) {
            return saved
        }
        let picked = pool.randomElement()
        if let chosen = picked {
            UserDefaults.standard.set(chosen.id, forKey: udKey)
        }
        return picked
    }

    // MARK: - Daily setup

    func isSetupDone(for date: Date = Date()) -> Bool {
        UserDefaults.standard.bool(forKey: "\(Self.setupDonePrefix)\(dateString(for: date))")
    }

    /// Fetches fresh entries, picks today's entry, schedules today's 9am notification.
    /// Idempotent — skips if already run today unless force == true.
    func runDailySetup(force: Bool = false) async {
        let today = Date()
        let doneKey = "\(Self.setupDonePrefix)\(dateString(for: today))"
        guard force || !UserDefaults.standard.bool(forKey: doneKey) else { return }

        guard let entries = try? await NotionService.shared.fetchBestOf(force: true) else { return }

        guard let entry = selectEntry(for: today, from: entries) else { return }
        await scheduleNineAM(for: today, entry: entry)

        UserDefaults.standard.set(true, forKey: doneKey)
    }

    // MARK: - 9am notification

    func scheduleNineAM(for date: Date, entry: BestOfEntry) async {
        let cal  = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day], from: date)
        comps.hour   = 9
        comps.minute = 0

        // Don't reschedule if it's already past 9am
        guard let fireTime = cal.date(from: comps), fireTime > Date() else { return }

        let center     = UNUserNotificationCenter.current()
        let identifier = "sunzzari-fallback-\(dateString(for: date))"
        center.removePendingNotificationRequests(withIdentifiers: [identifier])

        let content       = UNMutableNotificationContent()
        content.title     = "Today in Sunzzari"
        content.body      = "\(entry.category.emoji) \(entry.entry) — \(entry.year)"
        content.sound     = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        try? await center.add(request)
    }

    // MARK: - 12:01am midnight triggers

    /// Schedules a minimal 12:01am local notification for each of the next 30 nights.
    /// When the app is in the foreground at midnight, AppDelegate catches it and calls runDailySetup().
    /// On any other morning, ContentView.onChange(.active) catches it on first foreground.
    func scheduleMidnightTriggers() async {
        let center = UNUserNotificationCenter.current()
        let cal    = Calendar.current

        let pending  = await center.pendingNotificationRequests()
        let toRemove = pending
            .filter { $0.identifier.hasPrefix("sunzzari-midnight-") }
            .map(\.identifier)
        center.removePendingNotificationRequests(withIdentifiers: toRemove)

        for daysAhead in 1...30 {
            guard let date = cal.date(byAdding: .day, value: daysAhead, to: Date()) else { continue }
            var comps      = cal.dateComponents([.year, .month, .day], from: date)
            comps.hour     = 0
            comps.minute   = 1

            let content    = UNMutableNotificationContent()
            content.title  = "Today in Sunzzari"
            content.body   = "✨ A new day"
            content.sound  = nil
            if #available(iOS 15.0, *) {
                content.interruptionLevel = .passive
            }

            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let request = UNNotificationRequest(
                identifier: "sunzzari-midnight-\(dateString(for: date))",
                content:    content,
                trigger:    trigger
            )
            try? await center.add(request)
        }
    }

    // MARK: - Helpers

    func dateString(for date: Date) -> String {
        let cal   = Calendar(identifier: .gregorian)
        let comps = cal.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", comps.year ?? 0, comps.month ?? 0, comps.day ?? 0)
    }
}
