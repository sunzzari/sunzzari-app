import Foundation
import UIKit
import UserNotifications

enum BoopError: Error {
    case sendFailed
}

private struct NtfyEvent: Codable {
    let id: String
    let event: String
    let title: String?
    let message: String
    let tags: [String]?
}

final class BoopService: @unchecked Sendable {
    static let shared = BoopService()
    private init() {}

    private let baseURL = "https://ntfy.sh"
    private let topic = Constants.Boop.topic
    private let lastCheckKey = "sunzzari_boop_last_check"

    /// Stable 6-char device tag used to filter out own sent messages
    private var deviceTag: String {
        let raw = UIDevice.current.identifierForVendor?.uuidString
            .replacingOccurrences(of: "-", with: "").lowercased() ?? "unknown"
        return String(raw.prefix(6))
    }

    // MARK: - Send

    func send(message: String) async throws {
        guard let url = URL(string: "\(baseURL)/\(topic)") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Boop! 💛", forHTTPHeaderField: "X-Title")
        req.setValue("high", forHTTPHeaderField: "X-Priority")
        req.setValue("boop,\(deviceTag)", forHTTPHeaderField: "X-Tags")
        req.httpBody = message.data(using: .utf8)
        let (_, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            throw BoopError.sendFailed
        }
        // APNs push for instant delivery (ntfy above is the fallback for polling)
        await StatusService.shared.sendPush(title: "Boop! 💛", body: message)
    }

    // MARK: - Receive (foreground polling)

    func checkForBoops() async {
        let lastCheck = UserDefaults.standard.integer(forKey: lastCheckKey)
        let now = Int(Date().timeIntervalSince1970)
        UserDefaults.standard.set(now, forKey: lastCheckKey)

        // First launch: just record timestamp, no history to check
        guard lastCheck > 0 else { return }

        // Cap lookback to 1 hour to avoid replaying old boops
        let since = max(lastCheck, now - 3600)
        guard let url = URL(string: "\(baseURL)/\(topic)/json?since=\(since)") else { return }
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return }

        let lines = String(data: data, encoding: .utf8)?
            .components(separatedBy: "\n")
            .filter { !$0.isEmpty } ?? []

        for line in lines {
            guard
                let lineData = line.data(using: .utf8),
                let event = try? JSONDecoder().decode(NtfyEvent.self, from: lineData),
                event.event == "message"
            else { continue }

            // Skip boops sent from this device
            if (event.tags ?? []).contains(deviceTag) { continue }

            let currentBadge = await UIApplication.shared.applicationIconBadgeNumber
            let content = UNMutableNotificationContent()
            content.title = "Boop! 💛"
            content.body = event.message
            content.sound = .default
            content.badge = NSNumber(value: currentBadge + 1)
            let req = UNNotificationRequest(
                identifier: "sunzzari-boop-\(event.id)",
                content: content,
                trigger: nil // deliver immediately
            )
            try? await UNUserNotificationCenter.current().add(req)
        }
    }
}
