import SwiftUI
import PhotosUI
import UIKit

struct StoryComposeView: View {
    @Environment(\.dismiss) private var dismiss
    let onPosted: (StoryPost) -> Void

    @State private var pickerItem: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var caption: String = ""
    @State private var location: String = ""
    @State private var isPosting = false
    @State private var errorMessage: String?

    private var currentPerson: StoryPost.Person {
        AppIdentity.isHummingbird ? .cathy : .elisa
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.sunBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        photoArea
                        if image != nil {
                            captionField
                            locationField
                        }
                        if let errorMessage {
                            Text(errorMessage)
                                .font(.system(.caption, design: .serif))
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("New Story")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(Color.sunSurface, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.sunSecondary)
                        .disabled(isPosting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isPosting {
                        ProgressView().tint(.sunAccent)
                    } else {
                        Button("Post") { Task { await post() } }
                            .foregroundStyle(image == nil ? Color.sunSecondary : Color.sunAccent)
                            .fontWeight(.semibold)
                            .disabled(image == nil)
                    }
                }
            }
        }
    }

    // MARK: - Sections

    private var photoArea: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 480)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(alignment: .topTrailing) {
                        Button {
                            self.image = nil
                            self.pickerItem = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 24, design: .serif))
                                .foregroundStyle(Color.sunBackground)
                                .background(Color.black.opacity(0.4))
                                .clipShape(Circle())
                        }
                        .padding(10)
                    }
                    .overlay(alignment: .bottomLeading) {
                        if !caption.isEmpty {
                            Text(caption)
                                .font(.system(.body, design: .serif, weight: .medium))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Color.black.opacity(0.45))
                                .clipShape(Capsule())
                                .padding(16)
                        }
                    }
            } else {
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    VStack(spacing: 14) {
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 56, design: .serif))
                            .foregroundStyle(Color.sunAccent)
                        Text("Pick a photo")
                            .font(.system(.headline, design: .serif))
                            .foregroundStyle(Color.sunText)
                        Text("Posting as \(currentPerson.rawValue)")
                            .font(.system(.caption, design: .serif))
                            .foregroundStyle(Color.sunSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 320)
                    .background(Color.sunSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .onChange(of: pickerItem) { _, newItem in
                    Task { await loadPicked(newItem) }
                }
            }
        }
    }

    private var captionField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Caption", systemImage: "text.bubble")
                .font(.system(size: 12, weight: .medium, design: .serif))
                .foregroundStyle(Color.sunSecondary)
            TextField("Say something...", text: $caption, axis: .vertical)
                .lineLimit(1...4)
                .padding(12)
                .background(Color.sunSurface)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(Color.sunText)
        }
    }

    private var locationField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Where (optional)", systemImage: "mappin.and.ellipse")
                .font(.system(size: 12, weight: .medium, design: .serif))
                .foregroundStyle(Color.sunSecondary)
            TextField("Santa Monica", text: $location)
                .padding(12)
                .background(Color.sunSurface)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(Color.sunText)
        }
    }

    // MARK: - Actions

    private func loadPicked(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        do {
            if let data = try await item.loadTransferable(type: Data.self),
               let img = UIImage(data: data) {
                await MainActor.run {
                    self.image = img
                    self.errorMessage = nil
                }
            } else {
                // Library returned no data (iCloud download failed, low-fi
                // placeholder only). Reset the picker so the user can re-pick.
                await MainActor.run {
                    self.pickerItem = nil
                    self.errorMessage = "Couldn't load that photo. Try another."
                }
            }
        } catch {
            await MainActor.run {
                self.pickerItem = nil
                self.errorMessage = "Couldn't load that photo. Try another."
            }
        }
    }

    private func post() async {
        guard let image else { return }
        await MainActor.run {
            isPosting = true
            errorMessage = nil
        }
        defer { Task { @MainActor in isPosting = false } }

        do {
            let publicID = try await CloudinaryService.shared.uploadStory(image: image)
            let trimmedLocation = location.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedCaption = caption.trimmingCharacters(in: .whitespacesAndNewlines)
            let post = try await NotionService.shared.createStoryPost(
                publicID: publicID,
                caption: trimmedCaption,
                person: currentPerson,
                postedAt: Date(),
                location: trimmedLocation.isEmpty ? nil : trimmedLocation
            )
            // Notify the partner so they don't have to open the app to find out
            // a new story exists. Reuses StatusService's APNs fan-out via the
            // sunzzari-backend push endpoint.
            await StatusService.shared.sendPush(
                title: "\(currentPerson.rawValue) posted a story",
                body: trimmedCaption.isEmpty ? "Tap to watch" : trimmedCaption
            )
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            await MainActor.run {
                onPosted(post)
                dismiss()
            }
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
        }
    }
}
