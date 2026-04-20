import SwiftUI

struct WeeklyBestOfInputView: View {
    @Environment(\.dismiss) private var dismiss

    private static let prominent: [BestOfEntry.Category] = [
        .bestBites, .bestMoments, .funnyMoment, .bestLADates, .bestPurchase
    ]
    private static let more: [BestOfEntry.Category] = BestOfEntry.Category.allCases
        .filter { !prominent.contains($0) }

    @State private var drafts: [BestOfEntry.Category: [DraftEntry]] = {
        var map: [BestOfEntry.Category: [DraftEntry]] = [:]
        for cat in BestOfEntry.Category.allCases { map[cat] = [DraftEntry()] }
        return map
    }()
    @State private var showMoreCategories = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var savedMessage: String?

    struct DraftEntry: Identifiable {
        let id = UUID()
        var text: String = ""
        var hasDate: Bool = false
        var date: Date = Date()
    }

    private var totalFilled: Int {
        drafts.values.reduce(0) { acc, list in
            acc + list.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }.count
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.sunBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 22) {
                        header

                        ForEach(Self.prominent, id: \.self) { cat in
                            categorySection(cat)
                        }

                        DisclosureGroup(isExpanded: $showMoreCategories) {
                            VStack(spacing: 22) {
                                ForEach(Self.more, id: \.self) { cat in
                                    categorySection(cat)
                                }
                            }
                            .padding(.top, 12)
                        } label: {
                            Text("More categories")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.sunAccent)
                        }
                        .padding(.horizontal, 4)
                        .tint(Color.sunAccent)

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if let savedMessage {
                            Text(savedMessage)
                                .font(.caption)
                                .foregroundStyle(Color.sunAccent)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        saveAllButton
                    }
                    .padding(20)
                }
            }
            .navigationTitle("This Week")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(Color.sunSecondary)
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Log this week's highlights")
                .font(.title3.weight(.bold))
                .fontDesign(.serif)
                .foregroundStyle(Color.sunText)
            Text("Jot anything memorable. Add a date if you want; otherwise today is fine.")
                .font(.caption)
                .foregroundStyle(Color.sunSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func categorySection(_ cat: BestOfEntry.Category) -> some View {
        let accent = Color(hex: cat.colorHex)
        let list = drafts[cat] ?? []

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Rectangle()
                    .fill(accent)
                    .frame(width: 3, height: 20)
                    .clipShape(Capsule())
                Text(cat.emoji)
                Text(cat.rawValue)
                    .font(.headline)
                    .fontDesign(.serif)
                    .foregroundStyle(Color.sunText)
            }

            ForEach(list) { draft in
                draftRow(cat: cat, draft: draft, accent: accent)
            }

            Button {
                drafts[cat, default: []].append(DraftEntry())
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle")
                    Text("Add another")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(accent)
                .padding(.vertical, 6)
            }
        }
    }

    private func draftRow(cat: BestOfEntry.Category, draft: DraftEntry, accent: Color) -> some View {
        let binding = Binding<DraftEntry>(
            get: {
                drafts[cat]?.first(where: { $0.id == draft.id }) ?? draft
            },
            set: { newValue in
                if let idx = drafts[cat]?.firstIndex(where: { $0.id == draft.id }) {
                    drafts[cat]?[idx] = newValue
                }
            }
        )

        return VStack(spacing: 8) {
            HStack(spacing: 8) {
                TextField("e.g. \(placeholder(for: cat))", text: binding.text, axis: .vertical)
                    .lineLimit(1...3)
                    .padding(12)
                    .background(Color.sunSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(Color.sunText)

                if (drafts[cat]?.count ?? 0) > 1 {
                    Button {
                        drafts[cat]?.removeAll { $0.id == draft.id }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(Color.sunSecondary)
                    }
                }
            }

            HStack {
                Toggle(isOn: binding.hasDate) {
                    Text(binding.wrappedValue.hasDate
                         ? binding.wrappedValue.date.formatted(.dateTime.month(.abbreviated).day().year())
                         : "Use today")
                        .font(.caption)
                        .foregroundStyle(Color.sunSecondary)
                }
                .tint(accent)
            }

            if binding.wrappedValue.hasDate {
                DatePicker("", selection: binding.date, in: ...Date(), displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .tint(accent)
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(10)
        .background(Color.sunSurface.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var saveAllButton: some View {
        Button {
            Task { await saveAll() }
        } label: {
            HStack(spacing: 10) {
                if isSaving { ProgressView().tint(.sunBackground) }
                Text(isSaving ? "Saving..." : "Save All (\(totalFilled))")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(totalFilled == 0 ? Color.sunSurface : Color.sunAccent)
            .foregroundStyle(totalFilled == 0 ? Color.sunSecondary : Color.sunBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .disabled(totalFilled == 0 || isSaving)
    }

    private func placeholder(for cat: BestOfEntry.Category) -> String {
        switch cat {
        case .bestBites:      return "Il Latini, Florence"
        case .bestMoments:    return "Sunset at Malibu"
        case .funnyMoment:    return "The cat falling off the bookshelf"
        case .bestLADates:    return "Dinner at Gjelina"
        case .bestPurchase:   return "Ember mug"
        case .bestShow:       return "The Bear S3"
        case .bestMovie:      return "Challengers"
        case .worstMovie:     return "Madame Web"
        case .bestRestaurant: return "Kato"
        case .favoriteTrip:   return "Weekend in Ojai"
        case .favoriteGift:   return "Vintage cookbook"
        case .improvements:   return "Workout 4x/week"
        }
    }

    private func saveAll() async {
        isSaving = true
        errorMessage = nil
        savedMessage = nil
        defer { isSaving = false }

        let pending: [(BestOfEntry.Category, DraftEntry)] = drafts.flatMap { cat, list in
            list.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
                .map { (cat, $0) }
        }

        guard !pending.isEmpty else { return }

        var successCount = 0
        var firstError: Error?

        for (cat, draft) in pending {
            let entry = BestOfEntry(
                id:       UUID().uuidString,
                entry:    draft.text.trimmingCharacters(in: .whitespaces),
                date:     draft.hasDate ? draft.date : Date(),
                category: cat,
                notes:    ""
            )
            do {
                try await NotionService.shared.createBestOfEntry(entry)
                successCount += 1
            } catch {
                if firstError == nil { firstError = error }
            }
        }

        if successCount == pending.count {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        } else {
            savedMessage = "Saved \(successCount) of \(pending.count)"
            errorMessage = firstError?.localizedDescription
        }
    }
}
