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
    static let inboxDidChange     = Notification.Name("sunzzari.inboxDidChange")
    static let openInbox          = Notification.Name("sunzzari.openInbox")
    static let storiesDidMarkSeen = Notification.Name("sunzzari.storiesDidMarkSeen")
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

    /// Insert if missing, otherwise refresh title/subtitle/timestamp on an
    /// existing entry. Preserves `isRead`. Used by aggregating syncs (e.g.
    /// stories-by-day) so the entry reflects the latest snapshot of that
    /// bucket without growing inbox cardinality.
    func upsert(id: String, type: InboxEntryType, title: String, subtitle: String, timestamp: Date = Date()) {
        queue.async(flags: .barrier) {
            if let idx = self._entries.firstIndex(where: { $0.id == id }) {
                let prevRead = self._entries[idx].isRead
                self._entries[idx] = InboxEntry(
                    id: id, type: type, timestamp: timestamp,
                    title: title, subtitle: subtitle, isRead: prevRead
                )
            } else {
                let entry = InboxEntry(id: id, type: type, timestamp: timestamp,
                                       title: title, subtitle: subtitle, isRead: false)
                self._entries.insert(entry, at: 0)
            }
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

/// Tracks which story IDs the local user has already watched. Used by the
/// inbox sync so "Elisa posted N stories" reflects UNSEEN stories — total
/// daily count was misleading once you'd watched some of them. Stored in
/// UserDefaults as a string array; small footprint (story IDs are short and
/// stories age out after 24h, so this set stays bounded).
final class SeenStoriesStore: @unchecked Sendable {
    static let shared = SeenStoriesStore()

    private let key = "sunzzari_seen_story_ids"
    private let queue = DispatchQueue(label: "sunzzari.seenstories")
    private var ids: Set<String>

    private init() {
        ids = Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
    }

    func isSeen(_ id: String) -> Bool {
        queue.sync { ids.contains(id) }
    }

    func markSeen(_ id: String) {
        queue.sync {
            guard !ids.contains(id) else { return }
            ids.insert(id)
            UserDefaults.standard.set(Array(ids), forKey: key)
        }
    }

    func unseenCount(in stories: [StoryPost]) -> Int {
        queue.sync { stories.filter { !ids.contains($0.id) }.count }
    }
}
