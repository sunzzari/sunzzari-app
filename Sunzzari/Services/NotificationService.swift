import Foundation
import UserNotifications

final class NotificationService: @unchecked Sendable {
    static let shared = NotificationService()

    func requestPermission() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }

    /// Fires a test notification in 5 seconds using the real notification format.
    func sendTestNotification() async {
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = "Today in Sunzzari"
        content.body  = "✨ Met at Cliffs of ID — 2025"
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        let request = UNNotificationRequest(
            identifier: "sunzzari-test-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: trigger
        )
        try? await center.add(request)
    }

    /// Safety-net: schedules 9am notifications for the next 30 days using DailySetupService.selectEntry.
    /// Provides coverage for days the app is never opened and the 12:01am trigger doesn't run.
    /// DailySetupService.runDailySetup() overwrites today's notification with fresher data when it runs.
    func scheduleOnThisDay(allEntries: [BestOfEntry]) async {
        let center = UNUserNotificationCenter.current()

        // Clear existing 30-day schedule
        let pending  = await center.pendingNotificationRequests()
        let toRemove = pending
            .filter { $0.identifier.hasPrefix("sunzzari-otd-") || $0.identifier.hasPrefix("sunzzari-fallback-") }
            .map(\.identifier)
        center.removePendingNotificationRequests(withIdentifiers: toRemove)

        let cal = Calendar.current

        for daysAhead in 0..<30 {
            guard let date = cal.date(byAdding: .day, value: daysAhead, to: Date()) else { continue }

            // Delegate to the single source of truth
            guard let entry = DailySetupService.shared.selectEntry(for: date, from: allEntries) else { continue }

            var comps      = cal.dateComponents([.year, .month, .day], from: date)
            comps.hour     = 9
            comps.minute   = 0

            let trigger    = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let content    = UNMutableNotificationContent()
            content.title  = "Today in Sunzzari"
            content.body   = "\(entry.category.emoji) \(entry.entry) — \(entry.year)"
            content.sound  = .default

            let dateKey = DailySetupService.shared.dateString(for: date)
            let request = UNNotificationRequest(
                identifier: "sunzzari-fallback-\(dateKey)",
                content:    content,
                trigger:    trigger
            )
            try? await center.add(request)
        }
    }
}
