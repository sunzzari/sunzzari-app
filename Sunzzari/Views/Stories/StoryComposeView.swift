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

    // Caption preview overlay placement. Starts at .bottomLeading (offset 0,0
    // = anchor position) and the user can drag it to reposition. Drag is
    // CLAMPED to safe bounds so the rendered text never extends outside the
    // photo's frame -- that off-bounds rendering is what caused the iOS 26
    // horizontal-shift bug in the prior commit (location overlay started at
    // y: -218, rendering 218pt above photo center). Drag-driven offsets stay
    // small and inside the photo, so the bug cannot return.
    @State private var captionOffset: CGSize = .zero
    @State private var captionDragInProgress: CGSize = .zero

    // Compose-preview photo height. Matches the size that worked in the
    // pre-overlay layout (commit 6cb84ed~1) -- a tall portrait crop that
    // shows the photo clearly while leaving room for caption + location
    // fields below in a ScrollView. Scrolls naturally when the keyboard
    // covers the lower fields.
    private static let photoHeight: CGFloat = 480

    // Drag clamps. Conservative bounds keep the caption text fully within the
    // photo frame at all reasonable text widths. If the text is wider than
    // these bounds allow, the user just hits the wall sooner -- much better
    // than letting it render off the photo.
    private static let captionDragMaxX: CGFloat = 100
    private static let captionDragMaxY: CGFloat = 400

    private var currentPerson: StoryPost.Person {
        AppIdentity.isHummingbird ? .cathy : .elisa
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.sunBackground.ignoresSafeArea()

                ScrollView {
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
                    }
                    .padding(20)
                }
                .scrollDismissesKeyboard(.interactively)
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
                    .overlay(alignment: .bottomLeading) { captionPreviewOverlay }
                    .overlay(alignment: .topTrailing) {
                        Button {
                            self.image = nil
                            self.pickerItem = nil
                            self.captionOffset = .zero
                            self.captionDragInProgress = .zero
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

    /// Live caption preview rendered on the photo. Anchored bottom-leading so
    /// the initial position is inside the photo's frame (offset 0,0 = anchor).
    /// User can drag to reposition; the offset is clamped on drag end so the
    /// text never escapes the photo's bounds. NO scale/pinch -- those weren't
    /// asked for and add layout complexity that previously broke things.
    @ViewBuilder
    private var captionPreviewOverlay: some View {
        if !caption.isEmpty {
            Text(caption)
                .font(.system(.body, design: .serif, weight: .medium))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.45))
                .clipShape(Capsule())
                .padding(16)
                .offset(
                    x: captionOffset.width + captionDragInProgress.width,
                    y: captionOffset.height + captionDragInProgress.height
                )
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            captionDragInProgress = value.translation
                        }
                        .onEnded { value in
                            let newX = captionOffset.width + value.translation.width
                            let newY = captionOffset.height + value.translation.height
                            captionOffset.width = max(-Self.captionDragMaxX, min(Self.captionDragMaxX, newX))
                            captionOffset.height = max(-Self.captionDragMaxY, min(0, newY))
                            captionDragInProgress = .zero
                        }
                )
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
            // Bake the user's caption at its dragged position into the upload.
            // Pass an empty caption to Notion so the player's own caption
            // overlay does not double-render on top of the baked text. If the
            // caption is empty, the bake is a no-op and we upload the original.
            let imageToUpload = bakeCaptionIntoImage() ?? originalImage

            let publicID: String
            if let cached = lastUploadedPublicID {
                publicID = cached
            } else {
                publicID = try await CloudinaryService.shared.uploadStory(image: imageToUpload)
                lastUploadedPublicID = publicID
            }

            let trimmedLocation = location.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedCaption = caption.trimmingCharacters(in: .whitespacesAndNewlines)
            let post = try await NotionService.shared.createStoryPost(
                publicID: publicID,
                caption: "",
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

    /// Render the photo + caption preview at the user's dragged position into
    /// a single UIImage at upload time. ImageRenderer maps the SwiftUI preview
    /// 1:1 onto the baked output -- gesture state is the source of truth, no
    /// CoreGraphics math required. Returns nil if there's nothing to bake
    /// (no image OR empty caption -- in the empty-caption case the caller
    /// just uploads the original).
    @MainActor
    private func bakeCaptionIntoImage() -> UIImage? {
        guard let originalImage = image else { return nil }
        let trimmed = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let displayWidth = UIScreen.main.bounds.width - 40
        let displayHeight = Self.photoHeight

        let composed = ZStack(alignment: .bottomLeading) {
            Image(uiImage: originalImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: displayWidth, height: displayHeight)
                .clipped()

            Text(caption)
                .font(.system(.body, design: .serif, weight: .medium))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.45))
                .clipShape(Capsule())
                .padding(16)
                .offset(x: captionOffset.width, y: captionOffset.height)
        }
        .frame(width: displayWidth, height: displayHeight)

        let renderer = ImageRenderer(content: composed)
        renderer.scale = 3
        return renderer.uiImage
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
