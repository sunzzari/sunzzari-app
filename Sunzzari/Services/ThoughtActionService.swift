import Foundation

final class ThoughtActionService: @unchecked Sendable {
    static let shared = ThoughtActionService()
    private init() {}

    private let lastSeenKey = "sunzzari_thoughtaction_last_seen"

    /// Polls the thought-action DB for entries authored by the partner since last check.
    /// Appends one inbox entry per new partner-authored thought-action.
    /// First launch records the timestamp without backfilling history.
    func checkForNewEntries() async {
        let lastSeen = UserDefaults.standard.double(forKey: lastSeenKey)
        let now = Date().timeIntervalSince1970
        UserDefaults.standard.set(now, forKey: lastSeenKey)

        guard lastSeen > 0 else { return }

        let myAuthor = AppIdentity.current?.rawValue ?? "Hummingbird"
        let lastSeenDate = Date(timeIntervalSince1970: lastSeen)

        let entries: [ThoughtEntry]
        do {
            entries = try await NotionService.shared.fetchThoughts(force: true)
        } catch {
            return
        }

        let partnerNew = entries.filter { entry in
            entry.author != myAuthor && entry.date > lastSeenDate
        }

        for entry in partnerNew {
            NotificationInboxService.shared.append(
                id: "sunzzari-thoughtaction-\(entry.id)",
                type: .thoughtAction,
                title: "\(entry.author) added a thought",
                subtitle: entry.content,
                timestamp: entry.date
            )
        }
    }
}
