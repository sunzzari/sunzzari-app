import Foundation
import UserNotifications

final class NotificationService: @unchecked Sendable {
    static let shared = NotificationService()

    func requestPermission() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }

    /// Schedules one-time 9am notifications for the next 30 days using
    /// random unassigned Best Of entries (date == 1996-01-01).
    func scheduleOnThisDay(unassigned: [BestOfEntry]) async {
        let center = UNUserNotificationCenter.current()

        // Clear all existing Sunzzari notifications
        let pending = await center.pendingNotificationRequests()
        let toRemove = pending
            .filter { $0.identifier.hasPrefix("sunzzari-otd-") || $0.identifier.hasPrefix("sunzzari-fallback-") }
            .map(\.identifier)
        center.removePendingNotificationRequests(withIdentifiers: toRemove)

        guard !unassigned.isEmpty else { return }

        let cal = Calendar.current
        var pool = unassigned.shuffled()
        var poolIndex = 0

        for daysAhead in 0..<30 {
            guard let date = cal.date(byAdding: .day, value: daysAhead, to: Date()) else { continue }

            let entry = pool[poolIndex % pool.count]
            poolIndex += 1

            var components = cal.dateComponents([.year, .month, .day], from: date)
            components.hour   = 9
            components.minute = 0

            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

            let content = UNMutableNotificationContent()
            content.title = "\(entry.category.emoji) \(entry.category.rawValue)"
            content.body  = entry.entry
            content.sound = .default

            let dateKey = String(format: "%04d-%02d-%02d",
                components.year  ?? 0,
                components.month ?? 0,
                components.day   ?? 0)

            let request = UNNotificationRequest(
                identifier: "sunzzari-fallback-\(dateKey)",
                content:    content,
                trigger:    trigger
            )
            try? await center.add(request)
        }
    }
}
