import SwiftUI

struct AddCycleEntryView: View {
    @Environment(\.dismiss) private var dismiss

    let defaultDate: Date
    let entries: [CycleEntry]

    @State private var person: CycleEntry.Person = .elisa
    @State private var periodStart: Date
    @State private var avgCycleText: String = ""
    @State private var notes: String = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(defaultDate: Date = Date(), entries: [CycleEntry]) {
        self.defaultDate = defaultDate
        self.entries = entries
        _periodStart = State(initialValue: defaultDate)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.sunBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        formField(label: "Person", icon: "person.fill") {
                            Picker("Person", selection: $person) {
                                ForEach(CycleEntry.Person.allCases, id: \.self) { p in
                                    Text(p.rawValue).tag(p)
                                }
                            }
                            .pickerStyle(.segmented)
                        }

                        formField(label: "Period Start", icon: "calendar") {
                            DatePicker("", selection: $periodStart, displayedComponents: .date)
                                .datePickerStyle(.graphical)
                                .tint(.sunAccent)
                        }

                        formField(label: "Average Cycle (days)", icon: "arrow.clockwise") {
                            TextField("e.g. 28", text: $avgCycleText)
                                .keyboardType(.numberPad)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(Color.sunSurface)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .foregroundStyle(Color.sunText)
                        }

                        formField(label: "Notes (optional)", icon: "note.text") {
                            TextField("Any notes...", text: $notes)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(Color.sunSurface)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .foregroundStyle(Color.sunText)
                        }

                        if let err = errorMessage {
                            Text(err)
                                .font(.footnote)
                                .foregroundStyle(Color(hex: "#F87171"))
                                .multilineTextAlignment(.center)
                        }

                        Text("Tip: Link \"Previous Entry\" in Notion for auto cycle length calculation.")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.sunSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Add Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(Color.sunSurface, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.sunAccent)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView().tint(.sunAccent)
                    } else {
                        Button("Save") { Task { await save() } }
                            .foregroundStyle(Color.sunAccent)
                            .fontWeight(.semibold)
                    }
                }
            }
        }
        .onAppear { populateDefaults() }
        .onChange(of: person) { _, _ in populateDefaults() }
    }

    private func populateDefaults() {
        let latest = entries.filter { $0.person == person }.first
        if avgCycleText.isEmpty {
            avgCycleText = "\(latest?.avgCycle ?? (person == .elisa ? 28 : 30))"
        }
    }

    private func save() async {
        let avgCycle = Int(avgCycleText) ?? 28
        isSaving = true
        errorMessage = nil
        do {
            try await NotionService.shared.addCycleEntry(
                person: person,
                periodStart: periodStart,
                avgCycle: avgCycle,
                notes: notes
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }

    @ViewBuilder
    private func formField<C: View>(label: String, icon: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(label, systemImage: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.sunSecondary)
            content()
        }
    }
}
