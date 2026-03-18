import SwiftUI
import UIKit

struct StatusView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var hummingbird: StatusEntry?
    @State private var branch: StatusEntry?
    @State private var isLoading = true
    @State private var error: String?

    // Mood slider values
    @State private var hMood: Int = 50
    @State private var bMood: Int = 50
    @State private var hMoodCommitted: Int = 50
    @State private var bMoodCommitted: Int = 50

    // Adjective selections
    @State private var hAdjective: String = ""
    @State private var bAdjective: String = ""

    // Custom adjective text inputs
    @State private var hCustomText: String = ""
    @State private var bCustomText: String = ""

    static let adjectives: [(label: String, emoji: String)] = [
        ("Happy!",    "😄"),
        ("Grumpy",    "😠"),
        ("Hungry",    "🍕"),
        ("Work Mode", "💼"),
        ("Bidding",   "🤑"),
        ("Tired",     "😴"),
        ("Cozy",      "🛋️"),
        ("Excited",   "🤩"),
    ]

    var body: some View {
        ZStack {
            Color.sunBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Status")
                        .font(.system(size: 22, weight: .bold))
                        .fontDesign(.serif)
                        .foregroundStyle(Color.sunText)
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.sunSecondary)
                            .padding(8)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 16)

                Divider().background(Color.white.opacity(0.1))

                if isLoading {
                    Spacer()
                    ProgressView().tint(Color.sunAccent)
                    Spacer()
                } else if let error {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(Color.sunAccent)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(Color.sunSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    Spacer()
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            // Split panels — own panel is editable, partner panel is read-only
                            HStack(alignment: .top, spacing: 0) {
                                moodPanel(
                                    emoji: "🕊️",
                                    label: "HUMMINGBIRD",
                                    mood: $hMood,
                                    adjective: $hAdjective,
                                    updatedAt: hummingbird?.moodUpdatedAt,
                                    pageID: Constants.Status.hummingbirdPageID,
                                    fromName: "Hummingbird",
                                    isEditable: AppIdentity.isHummingbird
                                )

                                Divider()
                                    .background(Color.white.opacity(0.1))
                                    .frame(width: 1)

                                moodPanel(
                                    emoji: "🌿",
                                    label: "BRANCH",
                                    mood: $bMood,
                                    adjective: $bAdjective,
                                    updatedAt: branch?.moodUpdatedAt,
                                    pageID: Constants.Status.branchPageID,
                                    fromName: "Branch",
                                    isEditable: AppIdentity.isBranch
                                )
                            }

                            Divider().background(Color.white.opacity(0.1))

                            // Map
                            StatusMapView(entries: [hummingbird, branch].compactMap { $0 })
                                .frame(height: 280)
                        }
                    }
                }

                // Debug label — auto-hides once identity is set
                if AppIdentity.current == nil {
                    let raw = UIDevice.current.identifierForVendor?.uuidString
                        .replacingOccurrences(of: "-", with: "").lowercased() ?? "?"
                    Text("Debug — device prefix: \(String(raw.prefix(6)))")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color(hex: "#FBBF24"))
                        .padding(.vertical, 6)
                }
            }
        }
        .task { await load() }
        .onAppear { LocationService.shared.requestCurrentLocation() }
    }

    // MARK: - Panel

    private func moodPanel(
        emoji: String,
        label: String,
        mood: Binding<Int>,
        adjective: Binding<String>,
        updatedAt: Date?,
        pageID: String,
        fromName: String,
        isEditable: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Title
            HStack(spacing: 6) {
                Text(emoji).font(.title3)
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.sunSecondary)
                    .tracking(0.5)
            }

            // Slider — editable only for own panel
            BatterySlider(value: mood, isEditable: isEditable) { newVal in
                let committed = pageID == Constants.Status.hummingbirdPageID ? hMoodCommitted : bMoodCommitted
                guard newVal != committed else { return }
                if pageID == Constants.Status.hummingbirdPageID { hMoodCommitted = newVal }
                else { bMoodCommitted = newVal }
                Task {
                    try? await StatusService.shared.updateMood(newVal, for: pageID)
                    await StatusService.shared.sendMoodNotification(mood: newVal, fromName: fromName)
                }
            }

            // Adjective chips
            adjectiveGrid(selected: adjective, pageID: pageID, fromName: fromName, isEditable: isEditable)

            // Custom text input — own panel only
            if isEditable {
                let customBinding = pageID == Constants.Status.hummingbirdPageID ? $hCustomText : $bCustomText
                HStack(spacing: 6) {
                    TextField("or type one...", text: customBinding)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.sunText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color.white.opacity(0.07))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1))
                        .submitLabel(.done)
                        .onSubmit {
                            let text = customBinding.wrappedValue.trimmingCharacters(in: .whitespaces)
                            guard !text.isEmpty else { return }
                            adjective.wrappedValue = text
                            customBinding.wrappedValue = ""
                            Task {
                                try? await StatusService.shared.updateAdjective(text, for: pageID)
                                await StatusService.shared.sendAdjectiveNotification(
                                    adjective: text, fromName: fromName
                                )
                            }
                        }
                }
            }

            // Last updated timestamp
            if let ts = updatedAt {
                Text("last updated \(relativeTime(ts))")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.sunSecondary.opacity(0.7))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Adjective grid

    private func adjectiveGrid(
        selected: Binding<String>,
        pageID: String,
        fromName: String,
        isEditable: Bool
    ) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
            ForEach(Self.adjectives, id: \.label) { item in
                let isSelected = selected.wrappedValue == item.label
                Button {
                    guard isEditable else { return }
                    let newAdj = isSelected ? "" : item.label
                    selected.wrappedValue = newAdj
                    Task {
                        try? await StatusService.shared.updateAdjective(newAdj, for: pageID)
                        if !newAdj.isEmpty {
                            await StatusService.shared.sendAdjectiveNotification(
                                adjective: "\(item.label) \(item.emoji)",
                                fromName: fromName
                            )
                        }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Text(item.emoji).font(.system(size: 11))
                        Text(item.label)
                            .font(.system(size: 10, weight: .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(isSelected ? Color.sunBackground : Color.sunText)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity)
                    .background(isSelected ? Color.sunAccent : Color.white.opacity(0.07))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(
                        isSelected ? Color.sunAccent : Color.white.opacity(0.15),
                        lineWidth: 1
                    ))
                    .shadow(color: isSelected ? Color.sunAccent.opacity(0.4) : .clear, radius: 4)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Load

    private func load() async {
        guard !Constants.Status.hummingbirdPageID.isEmpty,
              !Constants.Status.branchPageID.isEmpty else {
            error = "Status DB not configured.\nFill in page IDs in Constants.Status."
            isLoading = false
            return
        }
        do {
            let (h, b) = try await StatusService.shared.fetchBoth()
            hummingbird = h
            branch = b
            hMood = h.mood;  hMoodCommitted = h.mood
            bMood = b.mood;  bMoodCommitted = b.mood
            hAdjective = h.adjective
            bAdjective = b.adjective
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - Helpers

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
