import SwiftUI

struct EditMemoryView: View {
    @Environment(\.dismiss) private var dismiss

    let onSave: (Memory) -> Void

    @State private var title: String
    @State private var date: Date
    @State private var category: Memory.Category
    @State private var notes: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let originalID: String
    private let originalPhotoURL: String?

    init(memory: Memory, onSave: @escaping (Memory) -> Void) {
        self.originalID = memory.id
        self.originalPhotoURL = memory.photoURL
        self.onSave = onSave
        _title    = State(initialValue: memory.title)
        _date     = State(initialValue: memory.date)
        _category = State(initialValue: memory.category)
        _notes    = State(initialValue: memory.notes)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.sunBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {

                        field(label: "Title", icon: "textformat") {
                            TextField("e.g. First trip to Paris", text: $title)
                                .padding()
                                .background(Color.sunSurface)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .foregroundStyle(Color.sunText)
                        }

                        field(label: "Date", icon: "calendar") {
                            DatePicker("", selection: $date, in: ...Date(), displayedComponents: .date)
                                .datePickerStyle(.graphical)
                                .tint(.sunAccent)
                                .padding()
                                .background(Color.sunSurface)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }

                        field(label: "Category", icon: "tag") {
                            HStack(spacing: 8) {
                                ForEach(Memory.Category.allCases, id: \.self) { cat in
                                    Button {
                                        category = cat
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    } label: {
                                        Text("\(cat.emoji) \(cat.rawValue)")
                                            .font(.caption.weight(.semibold))
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 10)
                                            .background(
                                                category == cat
                                                    ? Color(hex: cat.colorHex).opacity(0.3)
                                                    : Color.sunSurface
                                            )
                                            .foregroundStyle(
                                                category == cat
                                                    ? Color(hex: cat.colorHex)
                                                    : Color.sunSecondary
                                            )
                                            .clipShape(RoundedRectangle(cornerRadius: 10))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 10)
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

                        field(label: "Notes (optional)", icon: "note.text") {
                            TextField("What made this moment special?", text: $notes, axis: .vertical)
                                .lineLimit(3...6)
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
                            .background(title.isEmpty ? Color.sunSurface : Color.sunAccent)
                            .foregroundStyle(title.isEmpty ? Color.sunSecondary : Color.sunBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .disabled(title.isEmpty || isSaving)
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Edit Memory")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Color.sunSecondary)
                }
            }
        }
    }

    private func field<C: View>(label: String, icon: String, @ViewBuilder content: () -> C) -> some View {
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
            let updated = Memory(
                id:       originalID,
                title:    title,
                date:     date,
                category: category,
                notes:    notes,
                photoURL: originalPhotoURL
            )
            try await NotionService.shared.updateMemory(updated)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            onSave(updated)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
