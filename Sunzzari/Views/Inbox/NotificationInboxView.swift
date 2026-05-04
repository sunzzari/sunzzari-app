import SwiftUI

/// Bell icon with an unread-indicator dot for use in page headers.
/// Posts `.openInbox` on tap; ContentView observes and presents the inbox sheet.
struct InboxBellButton: View {
    @State private var unreadCount: Int = NotificationInboxService.shared.unreadCount

    var body: some View {
        Button {
            NotificationCenter.default.post(name: .openInbox, object: nil)
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "bell.fill")
                    .font(.system(size: 16, weight: .semibold, design: .serif))
                    .foregroundStyle(Color.sunAccent)
                    .padding(8)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Circle())

                if unreadCount > 0 {
                    Circle()
                        .fill(Color.sunAccent)
                        .frame(width: 8, height: 8)
                        .overlay(Circle().stroke(Color.sunBackground, lineWidth: 1.5))
                        .offset(x: 1, y: -1)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .inboxDidChange)) { _ in
            unreadCount = NotificationInboxService.shared.unreadCount
        }
    }
}

struct NotificationInboxView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var entries: [InboxEntry] = []

    let onRoute: (InboxEntry) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                Color.sunBackground.ignoresSafeArea()

                if entries.isEmpty {
                    emptyView
                } else {
                    List {
                        ForEach(grouped(), id: \.0) { (type, items) in
                            Section {
                                ForEach(items) { entry in
                                    row(entry)
                                        .listRowBackground(Color.sunSurface)
                                        .listRowSeparator(.hidden)
                                }
                            } header: {
                                header(for: type)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Inbox")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.sunAccent)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Clear all") {
                        NotificationInboxService.shared.clearAll()
                    }
                    .foregroundStyle(Color.sunAccent)
                    .disabled(entries.isEmpty)
                }
            }
            .onAppear { reload() }
            .onReceive(NotificationCenter.default.publisher(for: .inboxDidChange)) { _ in
                reload()
            }
        }
    }

    private var emptyView: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 36, weight: .light, design: .serif))
                .foregroundStyle(Color.sunSecondary.opacity(0.4))
            Text("No notifications")
                .font(.system(size: 14, design: .serif))
                .foregroundStyle(Color.sunSecondary)
            Text("Boops, status updates, and other prompts will land here.")
                .font(.system(size: 12, design: .serif))
                .foregroundStyle(Color.sunSecondary.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    private func grouped() -> [(InboxEntryType, [InboxEntry])] {
        let order: [InboxEntryType] = [.boop, .statusPrompt, .thoughtAction, .weeklyBestOf]
        let buckets = Dictionary(grouping: entries, by: \.type)
        return order.compactMap { type in
            guard let items = buckets[type], !items.isEmpty else { return nil }
            return (type, items.sorted { $0.timestamp > $1.timestamp })
        }
    }

    private func header(for type: InboxEntryType) -> some View {
        Text(label(for: type).uppercased())
            .font(.system(size: 11, weight: .semibold, design: .serif))
            .tracking(1.0)
            .foregroundStyle(Color.sunSecondary)
    }

    private func label(for type: InboxEntryType) -> String {
        switch type {
        case .boop:          return "Boops"
        case .statusPrompt:  return "Status"
        case .thoughtAction: return "Thought-Action"
        case .weeklyBestOf:  return "Weekly Best Of"
        }
    }

    private func row(_ entry: InboxEntry) -> some View {
        Button {
            NotificationInboxService.shared.markRead(entry.id)
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [entry.id])
            onRoute(entry)
            dismiss()
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Circle()
                    .fill(entry.isRead ? Color.clear : Color.sunAccent)
                    .frame(width: 8, height: 8)
                    .padding(.top, 7)

                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.title)
                        .font(.system(size: 15, weight: .semibold, design: .serif))
                        .foregroundStyle(.white)
                        .lineLimit(2)

                    if !entry.subtitle.isEmpty {
                        Text(entry.subtitle)
                            .font(.system(size: 13, design: .serif))
                            .foregroundStyle(Color.sunSecondary)
                            .lineLimit(2)
                    }

                    Text(relativeTime(entry.timestamp))
                        .font(.system(size: 11, design: .serif))
                        .foregroundStyle(Color.sunSecondary.opacity(0.6))
                }

                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    private func relativeTime(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: date, relativeTo: Date())
    }

    private func reload() {
        entries = NotificationInboxService.shared.entries
    }
}
