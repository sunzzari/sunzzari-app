import SwiftUI
import UIKit

/// Small coloured capsule under a row title (neighbourhood / streaming service /
/// Theaters vs At Home). Colour is derived from the text so a given value always
/// looks the same, with the common fixed values pinned to sensible colours.
struct ChecklistChip: View {
    let text: String

    private static let palette: [String] = [
        "#E8B86D", "#54A0FF", "#70C17C", "#A78BFA",
        "#F472B6", "#FBBF24", "#5EEAD4", "#FB923C"
    ]

    private static let pinned: [String: String] = [
        "theaters":    "#A78BFA",
        "at home":     "#70C17C",
        "netflix":     "#FF6B6B",
        "hulu":        "#70C17C",
        "max":         "#54A0FF",
        "disney+":     "#54A0FF",
        "prime video": "#5EEAD4",
        "apple tv+":   "#8E8E93",
        "peacock":     "#FB923C",
        "paramount+":  "#54A0FF",
        "other":       "#8E8E93"
    ]

    private var colorHex: String {
        let key = text.lowercased()
        if let pinned = Self.pinned[key] { return pinned }
        // Stable hash so the same neighbourhood keeps the same colour run to run.
        let hash = key.unicodeScalars.reduce(5381) { ($0 &* 33) &+ Int($1.value) }
        return Self.palette[abs(hash) % Self.palette.count]
    }

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold, design: .serif))
            .tracking(0.3)
            .foregroundStyle(Color(hex: colorHex))
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(Color(hex: colorHex).opacity(0.16))
            )
            .overlay(
                Capsule().stroke(Color(hex: colorHex).opacity(0.35), lineWidth: 0.5)
            )
    }
}

/// One Home checklist. All four lists render through this so they stay identical:
/// a tappable circle and a name, nothing else.
struct HomeChecklistRow: View {
    let item: ChecklistItem
    let isCompleting: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .strokeBorder(Color.sunSecondary.opacity(0.55), lineWidth: 1.5)
                        .frame(width: 20, height: 20)
                    if isCompleting {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(Color.sunAccent)
                    }
                }

                Text(item.title)
                    .font(.system(size: 15, design: .serif))
                    .foregroundStyle(Color.sunText)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .padding(.vertical, 7)
        }
        .buttonStyle(.plain)
        .disabled(isCompleting)
    }
}

/// Section header with an inline add button. Kept out of the List's `header:`
/// slot so the "+" stays tappable.
struct HomeChecklistHeader: View {
    let title: String
    let count: Int
    let onAdd: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(count > 0 ? "\(title) · \(count)" : title)
                .font(.system(size: 11, weight: .bold, design: .serif))
                .tracking(1.2)
                .foregroundStyle(Color.sunSecondary)
                .textCase(nil)

            Spacer(minLength: 0)

            Button(action: onAdd) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.sunAccent)
                    .padding(6)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }
}

/// Add sheet: name plus an optional chip. Restaurants type a neighbourhood;
/// movies and shows pick from a fixed set. Activities and recipes get name only.
struct HomeChecklistAddView: View {
    let list: HomeList
    let onSave: (String, String?) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var chip = ""
    @State private var isSaving = false
    @FocusState private var focused: Bool

    private var detentHeight: CGFloat {
        guard list.chipLabel != nil else { return 200 }
        return list.chipOptions.isEmpty ? 290 : 330
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.sunBackground.ignoresSafeArea()

                VStack(alignment: .leading, spacing: 18) {
                    TextField("", text: $text, prompt:
                        Text(list.addPrompt).foregroundStyle(Color.sunSecondary))
                        .font(.system(size: 17, design: .serif))
                        .foregroundStyle(Color.sunText)
                        .padding(14)
                        .background(Color.sunSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .focused($focused)
                        .submitLabel(.done)
                        .onSubmit { save() }

                    if let label = list.chipLabel {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(label.uppercased())
                                .font(.system(size: 10, weight: .bold, design: .serif))
                                .tracking(1.0)
                                .foregroundStyle(Color.sunSecondary)

                            if list.chipOptions.isEmpty {
                                // Restaurants: free text, neighbourhoods are open-ended.
                                TextField("", text: $chip, prompt:
                                    Text("Optional").foregroundStyle(Color.sunSecondary))
                                    .font(.system(size: 15, design: .serif))
                                    .foregroundStyle(Color.sunText)
                                    .padding(12)
                                    .background(Color.sunSurface)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            } else {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(list.chipOptions, id: \.self) { option in
                                            Button {
                                                chip = (chip == option) ? "" : option
                                            } label: {
                                                ChecklistChip(text: option)
                                                    .opacity(chip == option || chip.isEmpty ? 1 : 0.35)
                                                    .scaleEffect(chip == option ? 1.08 : 1.0)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                        }
                    }

                    Spacer(minLength: 0)
                }
                .padding(16)
            }
            .navigationTitle(list.title.capitalized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.sunSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { save() }
                        .foregroundStyle(Color.sunAccent)
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
        }
        .presentationDetents([.height(detentHeight)])
        .onAppear { focused = true }
    }

    private func save() {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !isSaving else { return }
        isSaving = true
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let tag = chip.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            await onSave(value, tag.isEmpty ? nil : tag)
            dismiss()
        }
    }
}

/// Next period for each of them, side by side. Read-only — logging still lives
/// on the Cycle screen.
struct HomeNextPeriodRow: View {
    let entries: [CycleEntry]

    var body: some View {
        HStack(spacing: 10) {
            ForEach(CycleEntry.Person.allCases, id: \.self) { person in
                card(for: person)
            }
        }
    }

    private func card(for person: CycleEntry.Person) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(person.rawValue)
                .font(.system(size: 11, weight: .semibold, design: .serif))
                .foregroundStyle(Color(hex: person.colorHex))

            if let predicted = CyclePrediction.predictedNext(in: entries, for: person) {
                let days = CyclePrediction.daysUntil(predicted)
                Text(Self.dateString(predicted))
                    .font(.system(size: 15, weight: .semibold, design: .serif))
                    .foregroundStyle(Color.sunText)
                Text(days < 0 ? "\(-days)d late"
                              : days == 0 ? "today"
                              : "in \(days)d")
                    .font(.system(size: 11, design: .serif))
                    .foregroundStyle(days < 0 ? Color(hex: person.colorHex) : Color.sunSecondary)
            } else {
                Text("No data yet")
                    .font(.system(size: 13, design: .serif))
                    .foregroundStyle(Color.sunSecondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.sunSurface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private static func dateString(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d"
        return fmt.string(from: date)
    }
}

/// Half-width card holding one checklist. Two per row, so the four lists cost
/// two screens' worth of height instead of four.
struct HomeChecklistCard: View {
    let list: HomeList
    let items: [ChecklistItem]
    let completing: Set<String>
    let onAdd: () -> Void
    let onComplete: (ChecklistItem) -> Void

    /// "Browse" goes to the hub we already built, unfiltered — not a
    /// shortlist-specific view.
    @ViewBuilder
    private var hubDestination: some View {
        switch list {
        case .restaurants: RestaurantHubView()
        default:           ActivitiesHubView()
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(list.shortTitle)
                    .font(.system(size: 10, weight: .bold, design: .serif))
                    .tracking(0.9)
                    .foregroundStyle(Color.sunSecondary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Button(action: onAdd) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.sunAccent)
                        .frame(width: 22, height: 22)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            if items.isEmpty {
                Text(list.emptyText)
                    .font(.system(size: 12, design: .serif))
                    .foregroundStyle(Color.sunSecondary.opacity(0.7))
                    .padding(.vertical, 2)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(items) { item in
                        Button {
                            onComplete(item)
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                ZStack {
                                    Circle()
                                        .strokeBorder(Color.sunSecondary.opacity(0.55), lineWidth: 1.4)
                                        .frame(width: 15, height: 15)
                                    if completing.contains(item.id) {
                                        ProgressView().controlSize(.mini).tint(Color.sunAccent)
                                    }
                                }
                                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 3 }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.title)
                                        .font(.system(size: 13, design: .serif))
                                        .foregroundStyle(Color.sunText)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                        .fixedSize(horizontal: false, vertical: true)

                                    if let chip = item.chip, !chip.isEmpty {
                                        ChecklistChip(text: chip)
                                    }
                                }

                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                            .padding(.vertical, 5)
                        }
                        .buttonStyle(.plain)
                        .disabled(completing.contains(item.id))
                    }
                }
            }

            if list.supportsBrowse {
                NavigationLink {
                    hubDestination
                } label: {
                    Text("Browse All")
                        .font(.system(size: 11, design: .serif))
                        .foregroundStyle(Color.sunAccent)
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.sunSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }
}
