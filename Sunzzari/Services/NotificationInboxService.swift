import Foundation
import UserNotifications

enum InboxEntryType: String, Codable {
    case boop
    case statusPrompt
    case thoughtAction
    case weeklyBestOf
    case storyUpdate
}

struct InboxEntry: Identifiable, Codable, Equatable {
    let id: String
    let type: InboxEntryType
    let timestamp: Date
    let title: String
    let subtitle: String
    var isRead: Bool
}

extension Notification.Name {
    static let inboxDidChange = Notification.Name("sunzzari.inboxDidChange")
    static let openInbox      = Notification.Name("sunzzari.openInbox")
}

final class NotificationInboxService: @unchecked Sendable {
    static let shared = NotificationInboxService()

    private init() { load() }

    private let queue = DispatchQueue(label: "sunzzari.inbox", attributes: .concurrent)
    private var _entries: [InboxEntry] = []

    private var fileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("notification_inbox.json")
    }

    var entries: [InboxEntry] { queue.sync { _entries } }

    var unreadCount: Int { queue.sync { _entries.filter { !$0.isRead }.count } }

    func append(id: String, type: InboxEntryType, title: String, subtitle: String, timestamp: Date = Date()) {
        queue.async(flags: .barrier) {
            if self._entries.contains(where: { $0.id == id }) { return }
            let entry = InboxEntry(id: id, type: type, timestamp: timestamp,
                                   title: title, subtitle: subtitle, isRead: false)
            self._entries.insert(entry, at: 0)
            self.persist()
            self.postChange()
        }
    }

    func markRead(_ id: String) {
        queue.async(flags: .barrier) {
            guard let idx = self._entries.firstIndex(where: { $0.id == id }) else { return }
            guard !self._entries[idx].isRead else { return }
            self._entries[idx].isRead = true
            self.persist()
            self.postChange()
        }
    }

    func clearAll() {
        queue.async(flags: .barrier) {
            self._entries.removeAll()
            self.persist()
            self.postChange()
        }
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(_entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let entries = try? decoder.decode([InboxEntry].self, from: data) {
            _entries = entries
        }
    }

    private func postChange() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .inboxDidChange, object: nil)
        }
    }
}
