import SwiftUI
import UIKit

/// Small coloured capsule under a row title (neighbourhood / streaming service /
/// Theaters vs At Home). Colour is derived from the text so a given value always
/// looks the same, with the common fixed values pinned to sensible colours.
struct ChecklistChip: View {
    let text: String
    /// Selected chips invert to a solid fill so the choice is unmistakable.
    var selected: Bool = false

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
            .font(.system(size: selected ? 11 : 9, weight: .semibold, design: .serif))
            .tracking(0.3)
            .foregroundStyle(selected ? Color.sunBackground : Color(hex: colorHex))
            .lineLimit(1)
            .padding(.horizontal, selected ? 10 : 7)
            .padding(.vertical, selected ? 5 : 3)
            .background(
                Capsule().fill(Color(hex: colorHex).opacity(selected ? 1.0 : 0.16))
            )
            .overlay(
                Capsule().stroke(Color(hex: colorHex).opacity(selected ? 1.0 : 0.35), lineWidth: selected ? 1 : 0.5)
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
    let onSave: (String, [String]) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var chip = ""          // restaurants: free text
    @State private var picked: Set<String> = []   // movies/shows/recipes: chips
    @State private var isSaving = false
    @FocusState private var focused: Bool

    private var detentHeight: CGFloat {
        guard list.chipLabel != nil else { return 200 }
        return list.chipOptions.isEmpty ? 290 : (list.chipOptions.count > 4 ? 400 : 330)
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
                            Text(list.allowsMultipleChips ? "\(label.uppercased()) · PICK ANY" : label.uppercased())
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
                                // A wrapping grid, NOT a horizontal ScrollView. The
                                // ScrollView swallowed every tap on these chips, so the
                                // picker looked right and did nothing.
                                LazyVGrid(
                                    columns: [GridItem(.adaptive(minimum: 96), spacing: 8, alignment: .leading)],
                                    alignment: .leading,
                                    spacing: 8
                                ) {
                                    ForEach(list.chipOptions, id: \.self) { option in
                                        Button {
                                            if picked.contains(option) {
                                                picked.remove(option)
                                            } else {
                                                // Only recipes may hold several at once.
                                                if !list.allowsMultipleChips { picked.removeAll() }
                                                picked.insert(option)
                                            }
                                        } label: {
                                            ChecklistChip(text: option, selected: picked.contains(option))
                                                .opacity(picked.isEmpty || picked.contains(option) ? 1 : 0.4)
                                        }
                                        .buttonStyle(.plain)
                                        .contentShape(Capsule())
                                    }
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
        let typed = chip.trimmingCharacters(in: .whitespacesAndNewlines)
        // Restaurants type a neighbourhood; everything else taps chips.
        let tags = list.chipOptions.isEmpty ? (typed.isEmpty ? [] : [typed])
                                            : list.chipOptions.filter { picked.contains($0) }
        Task {
            await onSave(value, tags)
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
    let onBrowse: () -> Void
    let onComplete: (ChecklistItem) -> Void

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

                                    if !item.chips.isEmpty {
                                        HStack(spacing: 4) {
                                            ForEach(item.chips, id: \.self) { ChecklistChip(text: $0) }
                                        }
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
                // Deliberately a Button, not a NavigationLink. A NavigationLink
                // inside a List row hands its tap area to the WHOLE row: all five
                // cards live in one row, so the entire block became a single link
                // to Activities and the checkboxes stopped responding.
                // Navigation is driven from TodayView instead.
                Button(action: onBrowse) {
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

/// The travel wishlist entry point on Home.
///
/// Deliberately renders NO destinations. Elisa's instruction (2026-08-24) was
/// "dont display all of the items. just add a place for me the input new ones
/// and link to the overall list" — so this is an add button and a link, nothing
/// more. It also means Home never fetches the wishlist, which keeps the tab's
/// load cost unchanged.
struct HomeTravelCard: View {
    let onAdd: () -> Void
    let onBrowse: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("TRAVEL")
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

            // A Button, not a NavigationLink — same reason as HomeChecklistCard:
            // a NavigationLink here hands its tap area to the whole List row.
            Button(action: onBrowse) {
                HStack(spacing: 4) {
                    Image(systemName: "globe.europe.africa.fill")
                        .font(.system(size: 11))
                    Text("View wishlist")
                        .font(.system(size: 13, design: .serif))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                }
                .foregroundStyle(Color.sunAccent)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .padding(.vertical, 5)
            }
            .buttonStyle(.plain)
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
