import SwiftUI
import PhotosUI
import UIKit
import AVFoundation

/// Compose sheet for a new story. Three failed iterations on the prior IG-style
/// overlay-on-photo + 9:16 canvas layout produced an unfixable horizontal-shift
/// bug on iOS 26.x where the form rows were clipped on the leading edge even
/// without the keyboard up. Root cause: the `.overlay { overlayLayer }` on the
/// photo, where the location text inside used `.offset(y: -218)` to position
/// itself above center, was leaking layout into the surrounding ScrollView.
/// This rewrite strips the overlay-on-photo + bake function entirely. Caption
/// is passed to Notion as a real string and the player renders it at playback
/// (StoryPlayerView caption overlay restored). No more drag/pinch positioning;
/// caption appears at a fixed position over the photo at playback time.
struct StoryComposeView: View {
    @Environment(\.dismiss) private var dismiss
    let onPosted: (StoryPost) -> Void

    @State private var pickerItem: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var caption: String = ""
    @State private var location: String = ""
    @State private var isPosting = false
    @State private var errorMessage: String?
    @State private var showSourceChoice = false
    @State private var showCamera = false
    @State private var showLibrary = false
    @State private var didAutoLaunchCamera = false

    // Cached publicID for retry: if Cloudinary upload succeeded but the
    // subsequent Notion createStoryPost failed, hold the publicID so a
    // retry does not re-upload (orphaning the first asset).
    @State private var lastUploadedPublicID: String?

    @FocusState private var isInputFocused: Bool

    // Fixed compose-preview height. Small enough that the form (photo +
    // caption + location) fits on screen above the keyboard without any
    // scroll, eliminating the keyboard-avoidance scroll path entirely.
    private static let photoHeight: CGFloat = 280

    private var currentPerson: StoryPost.Person {
        AppIdentity.isHummingbird ? .cathy : .elisa
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.sunBackground.ignoresSafeArea()

                VStack(spacing: 16) {
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
                    Spacer()
                }
                .padding(20)
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
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { isInputFocused = false }
                        .foregroundStyle(Color.sunAccent)
                }
            }
            .task { await maybeAutoLaunchCamera() }
        }
    }

    // MARK: - Sections

    private var photoArea: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .frame(height: Self.photoHeight)
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
            } else {
                Button {
                    showSourceChoice = true
                } label: {
                    VStack(spacing: 14) {
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 56, design: .serif))
                            .foregroundStyle(Color.sunAccent)
                        Text("Add a photo")
                            .font(.system(.headline, design: .serif))
                            .foregroundStyle(Color.sunText)
                        Text("Posting as \(currentPerson.rawValue)")
                            .font(.system(.caption, design: .serif))
                            .foregroundStyle(Color.sunSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: Self.photoHeight)
                    .background(Color.sunSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .confirmationDialog("Add a photo", isPresented: $showSourceChoice, titleVisibility: .hidden) {
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button("Take Photo") { showCamera = true }
                    }
                    Button("Choose from Library") { showLibrary = true }
                    Button("Cancel", role: .cancel) {}
                }
                .photosPicker(isPresented: $showLibrary, selection: $pickerItem, matching: .images)
                .onChange(of: pickerItem) { _, newItem in
                    Task { await loadPicked(newItem) }
                }
                .fullScreenCover(isPresented: $showCamera) {
                    CameraPicker { captured in
                        if let captured {
                            self.image = captured
                            self.errorMessage = nil
                        }
                    }
                    .ignoresSafeArea()
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
                .focused($isInputFocused)
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
                .focused($isInputFocused)
        }
    }

    // MARK: - Actions

    private func maybeAutoLaunchCamera() async {
        // Camera-first compose: open camera as soon as the sheet appears.
        // Permission gate avoids the black-screen UX on denied access.
        guard !didAutoLaunchCamera,
              image == nil,
              UIImagePickerController.isSourceTypeAvailable(.camera) else { return }
        didAutoLaunchCamera = true

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            showCamera = true
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if granted { showCamera = true }
        case .denied, .restricted:
            break
        @unknown default:
            break
        }
    }

    private func loadPicked(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        do {
            if let data = try await item.loadTransferable(type: Data.self),
               let img = UIImage(data: data) {
                // Downsample large Photos library assets (up to 48 MP on
                // newer iPhones) before holding them in memory. Without this
                // the compose sheet can OOM-crash on older devices the moment
                // a Pro photo is selected. 1080x1920 is the maximum resolution
                // Cloudinary will serve from an active story.
                let target = CGSize(width: 1080, height: 1920)
                let downsized = img.preparingThumbnail(of: target) ?? img
                await MainActor.run {
                    self.image = downsized
                    self.errorMessage = nil
                    self.lastUploadedPublicID = nil
                }
            } else {
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

    @MainActor
    private func post() async {
        guard let originalImage = image else { return }
        isPosting = true
        errorMessage = nil
        defer { isPosting = false }

        do {
            let publicID: String
            if let cached = lastUploadedPublicID {
                publicID = cached
            } else {
                publicID = try await CloudinaryService.shared.uploadStory(image: originalImage)
                lastUploadedPublicID = publicID
            }

            let trimmedLocation = location.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedCaption = caption.trimmingCharacters(in: .whitespacesAndNewlines)
            let post = try await NotionService.shared.createStoryPost(
                publicID: publicID,
                caption: trimmedCaption,
                person: currentPerson,
                postedAt: Date(),
                location: trimmedLocation.isEmpty ? nil : trimmedLocation
            )
            lastUploadedPublicID = nil

            // Push body uses caption -> location -> fallback. Recipient sees
            // push BEFORE photo loads, so a useful preview matters.
            let pushBody: String
            if !trimmedCaption.isEmpty {
                pushBody = trimmedCaption
            } else if !trimmedLocation.isEmpty {
                pushBody = trimmedLocation
            } else {
                pushBody = "Tap to watch"
            }
            await StatusService.shared.sendPush(
                title: "\(currentPerson.rawValue) posted a story",
                body: pushBody
            )
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            onPosted(post)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// SwiftUI wrapper for UIImagePickerController in camera mode. PhotosUI has no
/// camera-capture equivalent, so we drop down to UIKit. Closure-based instead
/// of @Binding so the caller can clear errorMessage atomically with setting
/// the image. nil = user cancelled.
private struct CameraPicker: UIViewControllerRepresentable {
    let onCaptured: (UIImage?) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            parent.onCaptured(info[.originalImage] as? UIImage)
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onCaptured(nil)
            parent.dismiss()
        }
    }
}
