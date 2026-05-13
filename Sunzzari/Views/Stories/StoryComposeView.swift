import SwiftUI
import PhotosUI
import UIKit
import AVFoundation

/// Instagram-style story compose. After capture, the photo fills the screen.
/// Tap anywhere to bring up a caption editor; the caption renders as a draggable
/// pill on the photo and is baked into the upload at post time. No separate
/// caption/location form -- one screen, one decision.
struct StoryComposeView: View {
    @Environment(\.dismiss) private var dismiss
    let onPosted: (StoryPost) -> Void

    @State private var pickerItem: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var caption: String = ""
    @State private var isPosting = false
    @State private var errorMessage: String?
    @State private var showSourceChoice = false
    @State private var showCamera = false
    @State private var showLibrary = false
    @State private var didAutoLaunchCamera = false
    @State private var cameraDecisionResolved = false

    // Caching the publicID lets a retry skip a second Cloudinary upload if
    // the first succeeded but Notion createStoryPost failed.
    @State private var lastUploadedPublicID: String?

    // Caption editor state. `isEditingCaption` toggles the inline TextField +
    // keyboard. Drag offsets are clamped on release so the caption pill never
    // escapes the visible photo area.
    @State private var isEditingCaption = false
    @State private var captionOffset: CGSize = .zero
    @State private var captionDragInProgress: CGSize = .zero

    @FocusState private var captionFocused: Bool

    private static let captionDragMaxX: CGFloat = 120
    private static let captionDragMaxY: CGFloat = 280

    private var currentPerson: StoryPost.Person {
        AppIdentity.isHummingbird ? .cathy : .elisa
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let image {
                composeStage(image: image)
            } else {
                pickerStage
            }

            if let errorMessage {
                VStack {
                    Spacer()
                    Text(errorMessage)
                        .font(.system(.footnote, design: .serif))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.red.opacity(0.85), in: Capsule())
                        .padding(.bottom, 120)
                }
                .transition(.opacity)
            }
        }
        .task { await maybeAutoLaunchCamera() }
    }

    // MARK: - Picker (pre-photo)

    private var pickerStage: some View {
        ZStack {
            if cameraDecisionResolved {
                VStack(spacing: 18) {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 56, design: .serif))
                        .foregroundStyle(Color.sunAccent)
                    Text("Add a photo")
                        .font(.system(.headline, design: .serif))
                        .foregroundStyle(.white)
                    Text("Posting as \(currentPerson.rawValue)")
                        .font(.system(.caption, design: .serif))
                        .foregroundStyle(.white.opacity(0.6))
                    HStack(spacing: 12) {
                        if UIImagePickerController.isSourceTypeAvailable(.camera) {
                            Button("Camera") { showCamera = true }
                                .buttonStyle(.borderedProminent)
                                .tint(Color.sunAccent)
                        }
                        Button("Library") { showLibrary = true }
                            .buttonStyle(.bordered)
                            .tint(.white)
                    }
                    .padding(.top, 6)
                }
            }

            // Cancel control, always present so the user can back out of the
            // sheet even before they've decided on a source.
            VStack {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                Spacer()
            }
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
        .fullScreenCover(isPresented: $showCamera, onDismiss: {
            // Camera closed without producing a photo (user tapped Cancel from
            // inside the system camera). Reveal the picker placeholder so they
            // have a path forward without dismissing the whole sheet.
            if image == nil {
                cameraDecisionResolved = true
            }
        }) {
            CameraPicker { captured in
                if let captured {
                    self.image = captured
                    self.errorMessage = nil
                }
            }
            .ignoresSafeArea()
        }
    }

    // MARK: - Compose (post-photo)

    private func composeStage(image: UIImage) -> some View {
        GeometryReader { geo in
            ZStack {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if !isEditingCaption {
                            isEditingCaption = true
                            captionFocused = true
                        }
                    }

                if isEditingCaption {
                    captionEditor
                } else if !caption.isEmpty {
                    captionPill
                } else {
                    captionHint
                }

                topBar
                bottomBar
            }
            .ignoresSafeArea()
        }
        .ignoresSafeArea()
    }

    private var topBar: some View {
        VStack {
            HStack {
                if !isEditingCaption {
                    Button {
                        // Discard the captured image, return to picker.
                        self.image = nil
                        self.caption = ""
                        self.captionOffset = .zero
                        self.captionDragInProgress = .zero
                        self.pickerItem = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                }

                Spacer()

                if isEditingCaption {
                    Button {
                        captionFocused = false
                        isEditingCaption = false
                    } label: {
                        Text("Done")
                            .font(.system(.subheadline, design: .serif, weight: .semibold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 8)
                            .background(Color.sunAccent, in: Capsule())
                    }
                } else if isPosting {
                    ProgressView().tint(.white)
                } else {
                    Button {
                        Task { await post() }
                    } label: {
                        Text("Post")
                            .font(.system(.subheadline, design: .serif, weight: .semibold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 8)
                            .background(Color.sunAccent, in: Capsule())
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            Spacer()
        }
    }

    /// Floating Aa button (bottom). Quick way back into the caption editor
    /// once a caption already exists, mirroring IG's text-tool affordance.
    private var bottomBar: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                if !isEditingCaption {
                    Button {
                        isEditingCaption = true
                        captionFocused = true
                    } label: {
                        Text("Aa")
                            .font(.system(.headline, design: .serif, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(.ultraThinMaterial, in: Circle())
                            .overlay(Circle().stroke(.white.opacity(0.3), lineWidth: 0.5))
                    }
                }
                Spacer()
            }
            .padding(.bottom, 32)
        }
    }

    private var captionHint: some View {
        VStack(spacing: 6) {
            Text("Aa")
                .font(.system(.title, design: .serif, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
            Text("Tap to add a caption")
                .font(.system(.footnote, design: .serif))
                .foregroundStyle(.white.opacity(0.7))
        }
        .shadow(color: .black.opacity(0.5), radius: 4)
        .allowsHitTesting(false)
    }

    private var captionPill: some View {
        Text(caption)
            .font(.system(.title3, design: .serif, weight: .semibold))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.45), in: Capsule())
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
                        captionOffset.height = max(-Self.captionDragMaxY, min(Self.captionDragMaxY, newY))
                        captionDragInProgress = .zero
                    }
            )
            .onTapGesture {
                isEditingCaption = true
                captionFocused = true
            }
    }

    /// In-place TextField overlaid on the photo. Centered horizontally so the
    /// editor reads like the final caption pill -- WYSIWYG-ish. Tapping Done
    /// commits and renders as a draggable pill.
    private var captionEditor: some View {
        VStack {
            Spacer().frame(height: 0)
            TextField("", text: $caption, axis: .vertical)
                .focused($captionFocused)
                .font(.system(.title3, design: .serif, weight: .semibold))
                .foregroundStyle(.white)
                .tint(Color.sunAccent)
                .multilineTextAlignment(.center)
                .lineLimit(1...4)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(Color.black.opacity(0.55), in: Capsule())
                .padding(.horizontal, 32)
                .onSubmit {
                    captionFocused = false
                    isEditingCaption = false
                }
            Spacer()
        }
        .padding(.top, 140)
    }

    // MARK: - Actions

    private func maybeAutoLaunchCamera() async {
        guard !didAutoLaunchCamera,
              image == nil,
              UIImagePickerController.isSourceTypeAvailable(.camera) else {
            cameraDecisionResolved = true
            return
        }
        didAutoLaunchCamera = true

        // Only reveal the picker placeholder when we're SURE camera will not
        // present. If camera presents, cameraDecisionResolved stays false so
        // the placeholder never shows behind the sliding fullScreenCover —
        // it'll be set true later when the camera dismisses without a photo.
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            showCamera = true
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if granted {
                showCamera = true
            } else {
                cameraDecisionResolved = true
            }
        case .denied, .restricted:
            cameraDecisionResolved = true
        @unknown default:
            cameraDecisionResolved = true
        }
    }

    private func loadPicked(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        do {
            if let data = try await item.loadTransferable(type: Data.self),
               let img = UIImage(data: data) {
                // Downsample large library assets (up to 48 MP on newer iPhones)
                // before holding them in memory. 1080x1920 is the max resolution
                // Cloudinary serves from an active story.
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
            // Bake the caption at its dragged position into the uploaded image.
            // Notion gets an empty caption string so the player's overlay does
            // not double-render on top of the baked text.
            let imageToUpload = bakeCaptionIntoImage() ?? originalImage

            let publicID: String
            if let cached = lastUploadedPublicID {
                publicID = cached
            } else {
                publicID = try await CloudinaryService.shared.uploadStory(image: imageToUpload)
                lastUploadedPublicID = publicID
            }

            let trimmedCaption = caption.trimmingCharacters(in: .whitespacesAndNewlines)
            let post = try await NotionService.shared.createStoryPost(
                publicID: publicID,
                caption: "",
                person: currentPerson,
                postedAt: Date(),
                location: nil
            )
            lastUploadedPublicID = nil

            let pushBody = trimmedCaption.isEmpty ? "Tap to watch" : trimmedCaption
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

    /// Bake photo + caption pill into a single UIImage at upload time. Uses
    /// ImageRenderer so gesture state is the source of truth -- no manual
    /// CoreGraphics math. Returns nil when there's no caption to bake (caller
    /// uploads the original photo instead).
    @MainActor
    private func bakeCaptionIntoImage() -> UIImage? {
        guard let originalImage = image else { return nil }
        let trimmed = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let screen = UIScreen.main.bounds.size

        let composed = ZStack {
            Image(uiImage: originalImage)
                .resizable()
                .scaledToFill()
                .frame(width: screen.width, height: screen.height)
                .clipped()

            Text(caption)
                .font(.system(.title3, design: .serif, weight: .semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(Color.black.opacity(0.45), in: Capsule())
                .offset(x: captionOffset.width, y: captionOffset.height)
        }
        .frame(width: screen.width, height: screen.height)

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
        if UIImagePickerController.isFlashAvailable(for: picker.cameraDevice) {
            picker.cameraFlashMode = .off
        }
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
