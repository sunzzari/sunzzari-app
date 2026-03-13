import SwiftUI

private let editAvailableYears = Array((2020...2026).reversed())

private func editYearOnlyDate(year: Int) -> Date {
    var c = DateComponents()
    c.year = year; c.month = 1; c.day = 1
    return Calendar(identifier: .gregorian).date(from: c) ?? Date()
}

struct EditEntryView: View {
    @Environment(\.dismiss) private var dismiss

    let onSave: (BestOfEntry) -> Void

    @State private var entryText: String
    @State private var category: BestOfEntry.Category
    @State private var hasDate: Bool
    @State private var selectedYear: Int
    @State private var date: Date
    @State private var notes: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let originalID: String

    init(entry: BestOfEntry, onSave: @escaping (BestOfEntry) -> Void) {
        self.originalID = entry.id
        self.onSave = onSave
        let isYearOnly = entry.isYearOnly
        _entryText    = State(initialValue: entry.entry)
        _category     = State(initialValue: entry.category)
        _hasDate      = State(initialValue: !isYearOnly)
        _selectedYear = State(initialValue: entry.year)
        _date         = State(initialValue: isYearOnly ? Date() : entry.date)
        _notes        = State(initialValue: entry.notes)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.sunBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {

                        formField(label: "Entry", icon: "star") {
                            TextField("e.g. Il Latini, Florence", text: $entryText)
                                .padding()
                                .background(Color.sunSurface)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .foregroundStyle(Color.sunText)
                        }

                        formField(label: "Category", icon: "tag") {
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                                ForEach(BestOfEntry.Category.allCases, id: \.self) { cat in
                                    Button {
                                        category = cat
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    } label: {
                                        VStack(spacing: 6) {
                                            Text(cat.emoji).font(.title2)
                                            Text(cat.rawValue)
                                                .font(.caption.weight(.semibold))
                                                .multilineTextAlignment(.center)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(
                                            category == cat
                                                ? Color(hex: cat.colorHex).opacity(0.25)
                                                : Color.sunSurface
                                        )
                                        .foregroundStyle(
                                            category == cat
                                                ? Color(hex: cat.colorHex)
                                                : Color.sunSecondary
                                        )
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .strokeBorder(
                                                    category == cat
                                                        ? Color(hex: cat.colorHex)
                                                        : Color.clear,
                                                    lineWidth: 1.5
                                                )
                                        )
                                    }
                                }
                            }
                        }

                        formField(label: "Date", icon: "calendar") {
                            VStack(spacing: 0) {
                                Toggle(isOn: $hasDate.animation(.easeInOut(duration: 0.2))) {
                                    Text(hasDate
                                         ? date.formatted(.dateTime.month(.wide).day().year())
                                         : "Year only — \(selectedYear)")
                                        .font(.subheadline)
                                        .foregroundStyle(Color.sunText)
                                }
                                .tint(.sunAccent)
                                .padding()
                                .background(Color.sunSurface)
                                .clipShape(RoundedRectangle(cornerRadius: 12))

                                if !hasDate {
                                    Picker("Year", selection: $selectedYear) {
                                        ForEach(editAvailableYears, id: \.self) { year in
                                            Text(String(year)).tag(year)
                                        }
                                    }
                                    .pickerStyle(.segmented)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .background(Color.sunSurface)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                }

                                if hasDate {
                                    DatePicker("", selection: $date, in: ...Date(), displayedComponents: .date)
                                        .datePickerStyle(.graphical)
                                        .tint(.sunAccent)
                                        .padding(.horizontal)
                                        .padding(.bottom)
                                        .background(Color.sunSurface)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                            }
                        }

                        formField(label: "Notes (optional)", icon: "note.text") {
                            TextField("Any context or story behind this?", text: $notes, axis: .vertical)
                                .lineLimit(3...5)
                                .padding()
                                .background(Color.sunSurface)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .foregroundStyle(Color.sunText)
                        }

                        if let errorMessage {
                            Text(errorMessage).font(.caption).foregroundStyle(.red)
                        }

                        Button {
                            Task { await save() }
                        } label: {
                            HStack(spacing: 10) {
                                if isSaving { ProgressView().tint(.sunBackground) }
                                Text(isSaving ? "Saving..." : "Save Changes")
                                    .font(.headline)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(entryText.isEmpty ? Color.sunSurface : Color.sunAccent)
                            .foregroundStyle(entryText.isEmpty ? Color.sunSecondary : Color.sunBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .disabled(entryText.isEmpty || isSaving)
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Edit Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Color.sunSecondary)
                }
            }
            .toolbarBackground(Color.sunBackground, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }

    private func formField<C: View>(label: String, icon: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(label, systemImage: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.sunSecondary)
            content()
        }
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            let updated = BestOfEntry(
                id:       originalID,
                entry:    entryText,
                date:     hasDate ? date : editYearOnlyDate(year: selectedYear),
                category: category,
                notes:    notes
            )
            try await NotionService.shared.updateBestOfEntry(updated)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            onSave(updated)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
