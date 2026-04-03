import Foundation
import UserNotifications

/// Single source of truth for "which entry to show on a given day."
/// Both TodayView and notifications call selectEntry() — they will always agree.
/// runDailySetup() is called on first foreground of the day (ContentView.onChange .active).
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

    /// Fetches fresh entries, syncs today's Tier-3 pick with Notion (so both phones agree),
    /// then schedules today's 9am notification. Idempotent unless force == true.
    func runDailySetup(force: Bool = false) async {
        let today = Date()
        let doneKey = "\(Self.setupDonePrefix)\(dateString(for: today))"
        guard force || !UserDefaults.standard.bool(forKey: doneKey) else { return }

        guard let entries = try? await NotionService.shared.fetchBestOf(force: true) else { return }

        // Sync the Tier-3 fallback pick through Notion so both phones show the same entry.
        // Only applies when there are no date-matched entries (pure Tier-3 day).
        let todayStr = dateString(for: today)
        let udKey = "\(Self.pickPrefix)\(todayStr)"
        let pool = entries.filter { $0.isYearOnly && $0.category != .improvements }
        if !pool.isEmpty {
            if let remoteID = await StatusService.shared.fetchTodayPick(for: todayStr),
               pool.first(where: { $0.id == remoteID }) != nil {
                // Partner already picked — adopt their choice
                UserDefaults.standard.set(remoteID, forKey: udKey)
            } else if let localID = UserDefaults.standard.string(forKey: udKey) {
                // We already picked locally — publish so partner sees it
                await StatusService.shared.storeTodayPick(dateStr: todayStr, entryID: localID)
            } else {
                // First phone to run today — pick and publish
                if let chosen = pool.randomElement() {
                    UserDefaults.standard.set(chosen.id, forKey: udKey)
                    await StatusService.shared.storeTodayPick(dateStr: todayStr, entryID: chosen.id)
                }
            }
        }

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

    // MARK: - Helpers

    func dateString(for date: Date) -> String {
        let cal   = Calendar(identifier: .gregorian)
        let comps = cal.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", comps.year ?? 0, comps.month ?? 0, comps.day ?? 0)
    }
}
