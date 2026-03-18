import SwiftUI

private let availableYears = Array((2020...2026).reversed())

private func yearOnlyDate(year: Int) -> Date {
    var c = DateComponents()
    c.year = year; c.month = 1; c.day = 1
    return Calendar(identifier: .gregorian).date(from: c) ?? Date()
}

struct AddEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var entryText = ""
    @State private var category: BestOfEntry.Category = .funnyMoment
    @State private var hasDate = false
    @State private var selectedYear = 2025
    @State private var date = Date()
    @State private var notes = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.sunBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {

                        // Entry title (required)
                        formField(label: "Entry", icon: "star") {
                            TextField("e.g. Il Latini, Florence", text: $entryText)
                                .padding()
                                .background(Color.sunSurface)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .foregroundStyle(Color.sunText)
                        }

                        // Category (required — always has a value)
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

                        // Date (year always known; specific day/month optional)
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
                                        ForEach(availableYears, id: \.self) { year in
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

                        // Notes (optional)
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
                                Text(isSaving ? "Saving..." : "Save Entry")
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
            .navigationTitle("New Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Color.sunSecondary)
                }
            }
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
            let entry = BestOfEntry(
                id:       UUID().uuidString,
                entry:    entryText,
                date:     hasDate ? date : yearOnlyDate(year: selectedYear),
                category: category,
                notes:    notes
            )
            try await NotionService.shared.createBestOfEntry(entry)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
