import SwiftUI
import PhotosUI

struct AddDinoView: View {
    let onSave: (DinosaurPhoto) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var selectedTags: Set<DinosaurPhoto.Tag> = []
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var isUploading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.sunBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // Photo picker
                        PhotosPicker(selection: $selectedItem, matching: .images) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color.sunSurface)
                                    .frame(height: 220)

                                if let image = selectedImage {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(height: 220)
                                        .clipped()
                                        .clipShape(RoundedRectangle(cornerRadius: 16))
                                } else {
                                    VStack(spacing: 12) {
                                        Image(systemName: "camera.fill")
                                            .font(.system(size: 40, design: .serif))
                                            .foregroundStyle(Color.sunAccent)
                                        Text("Tap to choose a photo")
                                            .font(.system(.subheadline, design: .serif))
                                            .foregroundStyle(Color.sunSecondary)
                                    }
                                }
                            }
                        }
                        .onChange(of: selectedItem) { _, newItem in
                            Task {
                                if let data = try? await newItem?.loadTransferable(type: Data.self),
                                   let image = UIImage(data: data) {
                                    selectedImage = image
                                }
                            }
                        }

                        // Name field
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

                        // Tags
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Tags", systemImage: "tag")
                                .font(.system(.caption, design: .serif, weight: .semibold))
                                .foregroundStyle(Color.sunSecondary)
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                                ForEach(DinosaurPhoto.Tag.allCases, id: \.self) { tag in
                                    Button {
                                        if selectedTags.contains(tag) {
                                            selectedTags.remove(tag)
                                        } else {
                                            selectedTags.insert(tag)
                                        }
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    } label: {
                                        HStack(spacing: 6) {
                                            Text(tag.emoji)
                                            Text(tag.rawValue)
                                                .font(.system(.subheadline, design: .serif, weight: .medium))
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
                            Text(errorMessage)
                                .font(.system(.caption, design: .serif))
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                        }

                        // Save button
                        Button {
                            Task { await save() }
                        } label: {
                            HStack(spacing: 10) {
                                if isUploading {
                                    ProgressView().tint(.sunBackground)
                                }
                                Text(isUploading ? "Uploading..." : "Save Dino")
                                    .font(.system(.headline, design: .serif))
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(canSave ? Color.sunAccent : Color.sunSurface)
                            .foregroundStyle(canSave ? Color.sunBackground : Color.sunSecondary)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .disabled(!canSave || isUploading)
                    }
                    .padding(20)
                }
            }
            .navigationTitle("New Dino")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.sunSecondary)
                }
            }
        }
    }

    private var canSave: Bool { !name.isEmpty && selectedImage != nil }

    private func save() async {
        guard let image = selectedImage else { return }
        isUploading = true
        errorMessage = nil
        defer { isUploading = false }

        do {
            let url = try await CloudinaryService.shared.upload(image: image)
            let photo = DinosaurPhoto(
                id:            UUID().uuidString,
                name:          name,
                cloudinaryURL: url,
                dateAdded:     Date(),
                isFavorite:    false,
                tags:          Array(selectedTags)
            )
            try await NotionService.shared.createDinosaur(photo)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            onSave(photo)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
