import Foundation
import CoreLocation
import UIKit
import UserNotifications

final class StatusService: @unchecked Sendable {
    static let shared = StatusService()
    private init() {}

    private let notionBase = "https://api.notion.com/v1"
    private let ntfyBase   = "https://ntfy.sh"
    private let lastCheckKey = "sunzzari_status_last_check"

    private var notionHeaders: [String: String] {
        [
            "Authorization":  "Bearer \(Constants.Notion.token)",
            "Notion-Version": Constants.Notion.version,
            "Content-Type":   "application/json"
        ]
    }

    /// Stable 6-char tag to identify this device's sends
    private var deviceTag: String {
        let raw = UIDevice.current.identifierForVendor?.uuidString
            .replacingOccurrences(of: "-", with: "").lowercased() ?? "unknown"
        return String(raw.prefix(6))
    }

    // MARK: - Fetch

    func fetchBoth() async throws -> (hummingbird: StatusEntry, branch: StatusEntry) {
        async let h = fetchPage(id: Constants.Status.hummingbirdPageID)
        async let b = fetchPage(id: Constants.Status.branchPageID)
        return try await (h, b)
    }

    private func fetchPage(id: String) async throws -> StatusEntry {
        guard !id.isEmpty, let url = URL(string: "\(notionBase)/pages/\(id)") else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        notionHeaders.forEach { req.setValue($1, forHTTPHeaderField: $0) }
        let (data, _) = try await URLSession.shared.data(for: req)
        return try parseEntry(from: data)
    }

    private func parseEntry(from data: Data) throws -> StatusEntry {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let id = json["id"] as? String,
            let props = json["properties"] as? [String: Any]
        else { throw URLError(.cannotParseResponse) }

        let name = (props["Name"] as? [String: Any])?["title"] as? [[String: Any]]
        let nameStr = name?.first?["plain_text"] as? String ?? ""

        let mood = (props["Mood"] as? [String: Any])?["number"] as? Int ?? 50

        let adjArr = (props["Adjective"] as? [String: Any])?["rich_text"] as? [[String: Any]]
        let adjective = adjArr?.compactMap { $0["plain_text"] as? String }.joined() ?? ""

        let moodUpdatedAt = parseDate(from: props["MoodUpdatedAt"])
        let lat  = (props["Latitude"]  as? [String: Any])?["number"] as? Double
        let lon  = (props["Longitude"] as? [String: Any])?["number"] as? Double
        let locUpdatedAt = parseDate(from: props["LocationUpdatedAt"])

        return StatusEntry(
            id: id,
            name: nameStr,
            mood: mood,
            adjective: adjective,
            moodUpdatedAt: moodUpdatedAt,
            latitude: lat,
            longitude: lon,
            locationUpdatedAt: locUpdatedAt
        )
    }

    private func parseDate(from prop: Any?) -> Date? {
        guard
            let d = prop as? [String: Any],
            let dateObj = d["date"] as? [String: Any],
            let str = dateObj["start"] as? String
        else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: str) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: str)
    }

    // MARK: - Update mood

    func updateMood(_ mood: Int, for pageID: String) async throws {
        let isoNow = isoString(for: Date())
        try await patchPage(id: pageID, body: [
            "properties": [
                "Mood":           ["number": mood],
                "MoodUpdatedAt":  ["date": ["start": isoNow]]
            ]
        ])
    }

    func updateAdjective(_ adjective: String, for pageID: String) async throws {
        try await patchPage(id: pageID, body: [
            "properties": [
                "Adjective": ["rich_text": [["text": ["content": adjective]]]],
                "MoodUpdatedAt": ["date": ["start": isoString(for: Date())]]
            ]
        ])
    }

    func sendAdjectiveNotification(adjective: String, fromName: String) async {
        let body = "\(fromName) is feeling: \(adjective)"
        // APNs (instant) — falls back to ntfy polling if token not yet stored
        await sendPush(title: "Status update 💛", body: body)
        // ntfy fallback
        guard let url = URL(string: "\(ntfyBase)/\(Constants.Status.ntfyTopic)") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Status update 💛", forHTTPHeaderField: "X-Title")
        req.setValue("default", forHTTPHeaderField: "X-Priority")
        req.setValue("status,\(deviceTag)", forHTTPHeaderField: "X-Tags")
        req.httpBody = body.data(using: .utf8)
        _ = try? await URLSession.shared.data(for: req)
    }

    // MARK: - Update location

    func updateLocation(_ coord: CLLocationCoordinate2D, for pageID: String) async throws {
        let isoNow = isoString(for: Date())
        try await patchPage(id: pageID, body: [
            "properties": [
                "Latitude":          ["number": coord.latitude],
                "Longitude":         ["number": coord.longitude],
                "LocationUpdatedAt": ["date": ["start": isoNow]]
            ]
        ])
    }

    // MARK: - APNs push (via Vercel backend)

    private let pendingTokenKey = "sunzzari_pending_apns_token"

    /// Store this device's APNs token in its own Notion Status page.
    /// Always caches the token in UserDefaults first. If identity is not yet set
    /// (first-launch race condition), the Notion write is deferred — call
    /// retryTokenStorage() after identity is confirmed in SettingsView.
    func storeDeviceToken(_ token: String) async {
        UserDefaults.standard.set(token, forKey: pendingTokenKey)
        guard AppIdentity.current != nil else { return }
        let ownPageID = AppIdentity.isBranch
            ? Constants.Status.branchPageID
            : Constants.Status.hummingbirdPageID
        try? await patchPage(id: ownPageID, body: [
            "properties": [
                "DeviceToken": ["rich_text": [["text": ["content": token]]]]
            ]
        ])
    }

    /// Re-attempt token storage after identity is confirmed.
    /// Call this from SettingsView when the user selects their identity.
    func retryTokenStorage() async {
        guard AppIdentity.current != nil else { return }
        guard let token = UserDefaults.standard.string(forKey: pendingTokenKey),
              !token.isEmpty else { return }
        let ownPageID = AppIdentity.isBranch
            ? Constants.Status.branchPageID
            : Constants.Status.hummingbirdPageID
        try? await patchPage(id: ownPageID, body: [
            "properties": [
                "DeviceToken": ["rich_text": [["text": ["content": token]]]]
            ]
        ])
    }

    /// Send an APNs push to the partner's device via the Vercel backend.
    /// Fetches the partner's DeviceToken from Notion, then POSTs to the push endpoint.
    func sendPush(title: String, body: String) async {
        let partnerPageID = AppIdentity.isBranch
            ? Constants.Status.hummingbirdPageID
            : Constants.Status.branchPageID

        guard let token = await fetchDeviceToken(pageID: partnerPageID), !token.isEmpty else { return }
        guard let url = URL(string: Constants.Status.pushEndpoint) else { return }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(Constants.Status.pushSecret, forHTTPHeaderField: "X-Sunzzari-Secret")
        let payload: [String: String] = ["title": title, "body": body, "deviceToken": token]
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        _ = try? await URLSession.shared.data(for: req)
    }

    private func fetchDeviceToken(pageID: String) async -> String? {
        guard let url = URL(string: "\(notionBase)/pages/\(pageID)") else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        notionHeaders.forEach { req.setValue($1, forHTTPHeaderField: $0) }
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let props = json["properties"] as? [String: Any],
              let rtArr = (props["DeviceToken"] as? [String: Any])?["rich_text"] as? [[String: Any]]
        else { return nil }
        return rtArr.compactMap { $0["plain_text"] as? String }.joined().nilIfEmpty
    }

    // MARK: - Shared Today pick (Today tab unification)

    /// Reads the shared Tier-3 pick from the Hummingbird Notion page.
    /// Format stored in TodayPick property: "YYYY-MM-DD:entryID"
    /// Returns the entryID only if the stored date matches today's dateStr.
    func fetchTodayPick(for dateStr: String) async -> String? {
        guard let url = URL(string: "\(notionBase)/pages/\(Constants.Status.hummingbirdPageID)") else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        notionHeaders.forEach { req.setValue($1, forHTTPHeaderField: $0) }
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let props = json["properties"] as? [String: Any],
              let rtArr = (props["TodayPick"] as? [String: Any])?["rich_text"] as? [[String: Any]]
        else { return nil }
        let value = rtArr.compactMap { $0["plain_text"] as? String }.joined()
        let parts = value.split(separator: ":", maxSplits: 1)
        guard parts.count == 2, String(parts[0]) == dateStr else { return nil }
        return String(parts[1])
    }

    /// Writes the shared Tier-3 pick to the Hummingbird Notion page.
    func storeTodayPick(dateStr: String, entryID: String) async {
        let value = "\(dateStr):\(entryID)"
        try? await patchPage(id: Constants.Status.hummingbirdPageID, body: [
            "properties": [
                "TodayPick": ["rich_text": [["text": ["content": value]]]]
            ]
        ])
    }

    // MARK: - Combined status update (mood + adjective in one Notion patch + one notification)

    func sendStatusUpdate(mood: Int, adjective: String, fromName: String, pageID: String) async {
        let isoNow = isoString(for: Date())
        var props: [String: Any] = [
            "Mood":          ["number": mood],
            "MoodUpdatedAt": ["date": ["start": isoNow]]
        ]
        props["Adjective"] = ["rich_text": [["text": ["content": adjective]]]]
        try? await patchPage(id: pageID, body: ["properties": props])

        let emoji = moodEmoji(for: mood)
        var body = "\(fromName) is feeling \(emoji) (\(mood)%)"
        if !adjective.isEmpty { body += " — \(adjective)" }

        await sendPush(title: "Status update", body: body)

        guard let url = URL(string: "\(ntfyBase)/\(Constants.Status.ntfyTopic)") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Status update", forHTTPHeaderField: "X-Title")
        req.setValue("default", forHTTPHeaderField: "X-Priority")
        req.setValue("status,\(deviceTag)", forHTTPHeaderField: "X-Tags")
        req.httpBody = body.data(using: .utf8)
        _ = try? await URLSession.shared.data(for: req)
    }

    // MARK: - ntfy mood notification

    func sendMoodNotification(mood: Int, fromName: String) async {
        let emoji = moodEmoji(for: mood)
        let body = "\(fromName) is feeling \(emoji) (\(mood)%)"
        // APNs (instant) — falls back to ntfy polling if token not yet stored
        await sendPush(title: "Status update 💛", body: body)
        // ntfy fallback
        guard let url = URL(string: "\(ntfyBase)/\(Constants.Status.ntfyTopic)") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Status update 💛", forHTTPHeaderField: "X-Title")
        req.setValue("default", forHTTPHeaderField: "X-Priority")
        req.setValue("status,\(deviceTag)", forHTTPHeaderField: "X-Tags")
        req.httpBody = body.data(using: .utf8)
        _ = try? await URLSession.shared.data(for: req)
    }

    // MARK: - Receive status notifications (foreground polling)

    func checkForStatus() async {
        let lastCheck = UserDefaults.standard.integer(forKey: lastCheckKey)
        let now = Int(Date().timeIntervalSince1970)
        UserDefaults.standard.set(now, forKey: lastCheckKey)

        guard lastCheck > 0 else { return }
        let since = max(lastCheck, now - 3600)
        guard let url = URL(string: "\(ntfyBase)/\(Constants.Status.ntfyTopic)/json?since=\(since)") else { return }
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return }

        let lines = String(data: data, encoding: .utf8)?
            .components(separatedBy: "\n")
            .filter { !$0.isEmpty } ?? []

        for line in lines {
            guard
                let lineData = line.data(using: .utf8),
                let event = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                let evType = event["event"] as? String, evType == "message",
                let message = event["message"] as? String,
                let tags = event["tags"] as? [String]
            else { continue }

            // Skip messages sent from this device
            if tags.contains(deviceTag) { continue }

            let evID = event["id"] as? String ?? UUID().uuidString
            let content = UNMutableNotificationContent()
            content.title = "Status update 💛"
            content.body = message
            content.sound = .default
            let req = UNNotificationRequest(
                identifier: "sunzzari-status-\(evID)",
                content: content,
                trigger: nil
            )
            try? await UNUserNotificationCenter.current().add(req)
        }
    }

    // MARK: - Helpers

    private func patchPage(id: String, body: [String: Any]) async throws {
        guard let url = URL(string: "\(notionBase)/pages/\(id)") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "PATCH"
        notionHeaders.forEach { req.setValue($1, forHTTPHeaderField: $0) }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        _ = try await URLSession.shared.data(for: req)
    }

    private func isoString(for date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }

    private func moodEmoji(for mood: Int) -> String {
        switch mood {
        case 0...20:  return "😴"
        case 21...40: return "😔"
        case 41...60: return "😊"
        case 61...80: return "🌟"
        default:      return "🔥"
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
