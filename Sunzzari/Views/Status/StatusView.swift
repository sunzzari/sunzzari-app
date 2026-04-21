import SwiftUI
import UIKit
import CoreLocation

struct StatusView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var hummingbird: StatusEntry?
    @State private var branch: StatusEntry?
    @State private var isLoading = true
    @State private var error: String?
    @State private var isSaving = false

    // Mood slider values
    @State private var hMood: Int = 50
    @State private var bMood: Int = 50

    // Adjective selections
    @State private var hAdjective: String = ""
    @State private var bAdjective: String = ""

    // Custom adjective text input
    @State private var customText: String = ""

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
                PageHeader("Status") {
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
                } else if let error {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(Color.sunAccent)
                        Text(error)
                            .font(.system(.caption, design: .serif))
                            .foregroundStyle(Color.sunSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    Spacer()
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            // Split panels
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
                        .font(.system(size: 11, weight: .medium, design: .serif))
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
                Text(emoji).font(.system(.title3, design: .serif))
                Text(label)
                    .font(.system(size: 10, weight: .medium, design: .serif))
                    .foregroundStyle(Color.sunSecondary)
                    .tracking(0.5)
            }

            // Slider — local state only, no immediate send
            BatterySlider(value: mood, isEditable: isEditable) { _ in }

            // Adjective chips — local state only
            adjectiveGrid(selected: adjective, isEditable: isEditable)

            // Custom text input — own panel only
            if isEditable {
                HStack(spacing: 6) {
                    TextField("or type one...", text: $customText)
                        .font(.system(size: 12, design: .serif))
                        .foregroundStyle(Color.sunText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color.white.opacity(0.07))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1))
                        .submitLabel(.done)
                        .onSubmit {
                            let text = customText.trimmingCharacters(in: .whitespaces)
                            guard !text.isEmpty else { return }
                            adjective.wrappedValue = text
                            customText = ""
                        }
                }
            }

            // Last updated timestamp
            if let ts = updatedAt {
                Text("last updated \(relativeTime(ts))")
                    .font(.system(size: 10, design: .serif))
                    .foregroundStyle(Color.sunSecondary.opacity(0.7))
            }

            // Submit button — own panel only
            if isEditable {
                Button {
                    isSaving = true
                    Task {
                        await StatusService.shared.sendStatusUpdate(
                            mood: mood.wrappedValue,
                            adjective: adjective.wrappedValue,
                            fromName: fromName,
                            pageID: pageID
                        )
                        // Refresh timestamps
                        if let (h, b) = try? await StatusService.shared.fetchBoth() {
                            hummingbird = h
                            branch = b
                        }
                        isSaving = false
                    }
                } label: {
                    HStack(spacing: 6) {
                        if isSaving {
                            ProgressView()
                                .tint(Color.sunBackground)
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 12, design: .serif))
                        }
                        Text(isSaving ? "Sending..." : "Send Status")
                            .font(.system(size: 13, weight: .semibold, design: .serif))
                    }
                    .foregroundStyle(Color.sunBackground)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.sunAccent)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(isSaving)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Adjective grid

    private func adjectiveGrid(
        selected: Binding<String>,
        isEditable: Bool
    ) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
            ForEach(Self.adjectives, id: \.label) { item in
                let isSelected = selected.wrappedValue == item.label
                Button {
                    guard isEditable else { return }
                    selected.wrappedValue = isSelected ? "" : item.label
                } label: {
                    HStack(spacing: 3) {
                        Text(item.emoji).font(.system(size: 11, design: .serif))
                        Text(item.label)
                            .font(.system(size: 10, weight: .medium, design: .serif))
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
            // If own Notion entry has no location yet, inject last-known coordinate
            // from UserDefaults so the map shows a pin immediately after first location fix.
            if let coord = LocationService.shared.lastKnownCoordinate {
                if AppIdentity.isHummingbird && h.latitude == nil {
                    hummingbird = StatusEntry(id: h.id, name: h.name, mood: h.mood,
                                             adjective: h.adjective, moodUpdatedAt: h.moodUpdatedAt,
                                             latitude: coord.latitude, longitude: coord.longitude,
                                             locationUpdatedAt: nil)
                } else if AppIdentity.isBranch && b.latitude == nil {
                    branch = StatusEntry(id: b.id, name: b.name, mood: b.mood,
                                        adjective: b.adjective, moodUpdatedAt: b.moodUpdatedAt,
                                        latitude: coord.latitude, longitude: coord.longitude,
                                        locationUpdatedAt: nil)
                }
            }
            hMood = hummingbird?.mood ?? 50
            bMood = branch?.mood ?? 50
            hAdjective = hummingbird?.adjective ?? ""
            bAdjective = branch?.adjective ?? ""
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
