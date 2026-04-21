import SwiftUI
import UIKit

struct ThoughtActionView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var entries: [ThoughtEntry] = []
    @State private var isLoading = true
    @State private var newText = ""
    @State private var isSending = false
    @FocusState private var inputFocused: Bool

    // Author determined by stored identity
    private var myAuthor: String {
        AppIdentity.current?.rawValue ?? "Hummingbird"
    }

    var body: some View {
        ZStack {
            Color.sunBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                PageHeader("Thought-Action") {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold, design: .serif))
                            .foregroundStyle(Color.sunSecondary)
                            .padding(8)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Circle())
                    }
                }

                if isLoading {
                    Spacer()
                    ProgressView().tint(Color.sunAccent)
                    Spacer()
                } else if entries.isEmpty {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.trianglebadge.exclamationmark")
                            .font(.system(size: 32, design: .serif))
                            .foregroundStyle(Color.sunSecondary.opacity(0.4))
                        Text("Nothing here")
                            .font(.system(size: 14, design: .serif))
                            .foregroundStyle(Color.sunSecondary)
                        Text("Write something, then check it off when done.")
                            .font(.system(size: 12, design: .serif))
                            .foregroundStyle(Color.sunSecondary.opacity(0.6))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 40)
                    Spacer()
                } else {
                    List {
                        ForEach(entries) { entry in
                            entryRow(entry)
                                .listRowBackground(Color.clear)
                                .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                                .listRowSeparator(.hidden)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .refreshable { await reload() }
                }

                Divider().background(Color.white.opacity(0.1))

                // Input area
                HStack(spacing: 10) {
                    Text(myAuthor == "Branch" ? "🌿" : "🕊️")
                        .font(.system(size: 18, design: .serif))

                    TextField("write something...", text: $newText, axis: .vertical)
                        .font(.system(size: 15, design: .serif))
                        .foregroundStyle(Color.sunText)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(Color.white.opacity(0.07))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.12), lineWidth: 1))
                        .lineLimit(1...4)
                        .focused($inputFocused)

                    Button {
                        Task { await send() }
                    } label: {
                        if isSending {
                            ProgressView()
                                .tint(Color.sunBackground)
                                .frame(width: 36, height: 36)
                                .background(Color(hex: "#C084FC"))
                                .clipShape(Circle())
                        } else {
                            let isEmpty = newText.trimmingCharacters(in: .whitespaces).isEmpty
                            Image(systemName: "arrow.up")
                                .font(.system(size: 16, weight: .bold, design: .serif))
                                .foregroundStyle(isEmpty ? Color.sunSecondary : Color.sunBackground)
                                .frame(width: 36, height: 36)
                                .background(isEmpty ? Color.white.opacity(0.1) : Color(hex: "#C084FC"))
                                .clipShape(Circle())
                        }
                    }
                    .disabled(newText.trimmingCharacters(in: .whitespaces).isEmpty || isSending)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .task { await load() }
    }

    // MARK: - Entry row

    private func entryRow(_ entry: ThoughtEntry) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // Done button — tap to archive + remove
            Button {
                markDone(entry)
            } label: {
                Circle()
                    .stroke(Color(hex: entry.authorColorHex).opacity(0.6), lineWidth: 1.5)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .padding(.top, 1)

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.content)
                    .font(.system(size: 15, design: .serif))
                    .fontDesign(.serif)
                    .foregroundStyle(Color.sunText)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 4) {
                    Text(entry.authorEmoji)
                        .font(.system(size: 10, design: .serif))
                    Text(entry.author)
                        .font(.system(size: 10, weight: .medium, design: .serif))
                        .foregroundStyle(Color(hex: entry.authorColorHex).opacity(0.8))
                    Text("·")
                        .font(.system(size: 10, design: .serif))
                        .foregroundStyle(Color.sunSecondary)
                    Text(relativeTime(entry.date))
                        .font(.system(size: 10, design: .serif))
                        .foregroundStyle(Color.sunSecondary)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Color.sunSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08), lineWidth: 1))
    }

    // MARK: - Actions

    private func load() async {
        if let disk = NotionService.shared.thoughtsDiskCache(), !disk.isEmpty {
            entries = disk
            isLoading = false
        }
        await reload()
    }

    private func reload() async {
        do {
            entries = try await NotionService.shared.fetchThoughts(force: true)
        } catch is CancellationError { }
        catch { }
        isLoading = false
    }

    private func send() async {
        let text = newText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        isSending = true
        newText = ""
        inputFocused = false
        do {
            try await NotionService.shared.addThought(content: text, author: myAuthor)
            entries = try await NotionService.shared.fetchThoughts(force: true)
        } catch { }
        isSending = false
    }

    private func markDone(_ entry: ThoughtEntry) {
        withAnimation(.easeOut(duration: 0.2)) {
            entries.removeAll { $0.id == entry.id }
        }
        Task { try? await NotionService.shared.archivePage(id: entry.id) }
    }

    private func relativeTime(_ date: Date) -> String {
        let diff = Int(Date().timeIntervalSince(date))
        switch diff {
        case ..<60:        return "just now"
        case 60..<3600:    return "\(diff / 60)m ago"
        case 3600..<86400: return "\(diff / 3600)h ago"
        default:           return "\(diff / 86400)d ago"
        }
    }
}
