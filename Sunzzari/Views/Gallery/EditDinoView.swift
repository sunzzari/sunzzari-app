import SwiftUI

struct EditDinoView: View {
    @Environment(\.dismiss) private var dismiss

    let onSave: (DinosaurPhoto) -> Void

    @State private var name: String
    @State private var selectedTags: Set<DinosaurPhoto.Tag>
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let original: DinosaurPhoto

    init(photo: DinosaurPhoto, onSave: @escaping (DinosaurPhoto) -> Void) {
        self.original = photo
        self.onSave = onSave
        _name         = State(initialValue: photo.name)
        _selectedTags = State(initialValue: Set(photo.tags))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.sunBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {

                        VStack(alignment: .leading, spacing: 8) {
                            Label("Name", systemImage: "textformat")
                                .font(.system(.caption, design: .serif, weight: .semibold))
                                .foregroundStyle(Color.sunSecondary)
                            TextField("e.g. Dino at Sunset", text: $name)
                                .padding()
                                .background(Color.sunSurface)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .foregroundStyle(Color.sunText)
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            Label("Tags", systemImage: "tag")
                                .font(.system(.caption, design: .serif, weight: .semibold))
                                .foregroundStyle(Color.sunSecondary)
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                                ForEach(DinosaurPhoto.Tag.allCases, id: \.self) { tag in
                                    Button {
                                        if selectedTags.contains(tag) { selectedTags.remove(tag) }
                                        else { selectedTags.insert(tag) }
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    } label: {
                                        HStack(spacing: 6) {
                                            Text(tag.emoji)
                                            Text(tag.rawValue).font(.system(.subheadline, design: .serif, weight: .medium))
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(
                                            selectedTags.contains(tag)
                                                ? Color(hex: tag.color).opacity(0.3)
                                                : Color.sunSurface
                                        )
                                        .foregroundStyle(
                                            selectedTags.contains(tag)
                                                ? Color(hex: tag.color)
                                                : Color.sunSecondary
                                        )
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10)
                                                .strokeBorder(
                                                    selectedTags.contains(tag)
                                                        ? Color(hex: tag.color)
                                                        : Color.clear,
                                                    lineWidth: 1.5
                                                )
                                        )
                                    }
                                }
                            }
                        }

                        if let errorMessage {
                            Text(errorMessage).font(.system(.caption, design: .serif)).foregroundStyle(.red)
                        }

                        Button {
                            Task { await save() }
                        } label: {
                            HStack(spacing: 10) {
                                if isSaving { ProgressView().tint(.sunBackground) }
                                Text(isSaving ? "Saving..." : "Save Changes")
                                    .font(.system(.headline, design: .serif))
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(name.isEmpty ? Color.sunSurface : Color.sunAccent)
                            .foregroundStyle(name.isEmpty ? Color.sunSecondary : Color.sunBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .disabled(name.isEmpty || isSaving)
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Edit Dino")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Color.sunSecondary)
                }
            }
        }
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            var updated = original
            updated.name = name
            updated.tags = Array(selectedTags)
            try await NotionService.shared.updateDinosaur(updated)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            onSave(updated)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
