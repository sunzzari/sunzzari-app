import SwiftUI
import PhotosUI
import UIKit
import AVFoundation

struct StoryComposeView: View {
    @Environment(\.dismiss) private var dismiss
    let onPosted: (StoryPost) -> Void

    @State private var pickerItem: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var caption: String = ""
    @State private var location: String = ""
    @State private var isPosting = false
    @State private var errorMessage: String?
    // Source-choice state. The simulator has no camera, so isSourceTypeAvailable
    // returns false there and the dialog only shows "Choose from Library".
    @State private var showSourceChoice = false
    @State private var showCamera = false
    @State private var showLibrary = false
    // One-shot guard: open the camera automatically the first time the sheet
    // appears (Snap-style camera-first compose). After the user cancels the
    // camera or selects an image, this stays true so the picker is not re-
    // launched on every body re-render.
    @State private var didAutoLaunchCamera = false

    // Caption + location overlay placement. Default y-offsets put caption
    // toward the photo bottom and location toward the photo top, scaled to
    // 35% of the photo height so they remain in the same proportional spot
    // whether the preview is short or full-screen-tall. User drags to
    // override and pinches to resize. Committed values persist between
    // gestures; in-progress values render the live transform.
    @State private var captionOffset: CGSize = CGSize(width: 0, height: StoryComposeView.composedPhotoHeight * 0.35)
    @State private var captionDragInProgress: CGSize = .zero
    @State private var captionScale: CGFloat = 1
    @State private var captionMagnifyInProgress: CGFloat = 1
    @State private var locationOffset: CGSize = CGSize(width: 0, height: -StoryComposeView.composedPhotoHeight * 0.35)
    @State private var locationDragInProgress: CGSize = .zero
    @State private var locationScale: CGFloat = 1
    @State private var locationMagnifyInProgress: CGFloat = 1

    // Cached publicID for retry: if Cloudinary upload succeeded but the
    // subsequent Notion createStoryPost failed, we hold the publicID so a
    // user-tapped retry does not re-upload (orphaning the first asset).
    // Cleared on full-chain success or on photo replacement.
    @State private var lastUploadedPublicID: String?

    /// Compose preview height matches the player's full-screen aspect ratio so
    /// what the user sees in compose is exactly what plays back. Without this,
    /// a 480pt-tall preview baked overlays at the photo edges get cropped when
    /// the player scaledToFill the full screen aspect (~9:19.5 on iPhone).
    private static var composedPhotoHeight: CGFloat {
        let bounds = UIScreen.main.bounds
        let composeContentWidth = bounds.width - 40
        return composeContentWidth * (bounds.height / bounds.width)
    }

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
            }
            .task {
                // Camera-first compose: open the camera as soon as the sheet
                // appears, with the source-choice dialog as the fallback path
                // (Cancel from the camera returns to the empty placeholder, a
                // tap on which still gives Take Photo / Choose from Library).
                // Skip on simulator (no camera) so the test path stays clean.
                // Permission gate: avoid the black-screen UX on denied camera
                // by requesting access first; on deny, fall through to the
                // placeholder so the user can still pick from library.
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
                    .frame(height: Self.composedPhotoHeight)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay {
                        overlayLayer
                    }
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
                    .frame(height: 320)
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

    /// Overlays for caption + location. Each is independently draggable and
    /// pinch-resizable. SimultaneousGesture lets the user drag and pinch at
    /// once. Hidden when the underlying string is empty so an empty TextField
    /// doesn't paint a stray capsule on the photo.
    private var overlayLayer: some View {
        ZStack {
            if !caption.isEmpty {
                Text(caption)
                    .font(.system(.body, design: .serif, weight: .medium))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.45))
                    .clipShape(Capsule())
                    .scaleEffect(captionScale * captionMagnifyInProgress)
                    .offset(
                        x: captionOffset.width + captionDragInProgress.width,
                        y: captionOffset.height + captionDragInProgress.height
                    )
                    .gesture(overlayGesture(
                        offset: $captionOffset,
                        drag: $captionDragInProgress,
                        scale: $captionScale,
                        magnify: $captionMagnifyInProgress
                    ))
            }

            if !location.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "mappin.and.ellipse")
                    Text(location)
                }
                .font(.system(.subheadline, design: .serif, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.45))
                .clipShape(Capsule())
                .scaleEffect(locationScale * locationMagnifyInProgress)
                .offset(
                    x: locationOffset.width + locationDragInProgress.width,
                    y: locationOffset.height + locationDragInProgress.height
                )
                .gesture(overlayGesture(
                    offset: $locationOffset,
                    drag: $locationDragInProgress,
                    scale: $locationScale,
                    magnify: $locationMagnifyInProgress
                ))
            }
        }
    }

    private func overlayGesture(
        offset: Binding<CGSize>,
        drag: Binding<CGSize>,
        scale: Binding<CGFloat>,
        magnify: Binding<CGFloat>
    ) -> some Gesture {
        SimultaneousGesture(
            DragGesture()
                .onChanged { value in
                    drag.wrappedValue = value.translation
                }
                .onEnded { value in
                    offset.wrappedValue.width += value.translation.width
                    offset.wrappedValue.height += value.translation.height
                    drag.wrappedValue = .zero
                },
            MagnifyGesture()
                .onChanged { value in
                    magnify.wrappedValue = value.magnification
                }
                .onEnded { value in
                    let next = scale.wrappedValue * value.magnification
                    scale.wrappedValue = max(0.5, min(3.0, next))
                    magnify.wrappedValue = 1
                }
        )
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
                // Downsample large Photos library assets (up to 48 MP on
                // newer iPhones) before holding them in memory. Without this
                // the compose sheet can OOM-crash on older devices the
                // moment a Pro photo is selected. 1080x1920 is the maximum
                // resolution Cloudinary will serve from an active story
                // anyway, so additional pixels would be wasted on upload.
                let target = CGSize(width: 1080, height: 1920)
                let downsized = img.preparingThumbnail(of: target) ?? img
                await MainActor.run {
                    self.image = downsized
                    self.errorMessage = nil
                    self.lastUploadedPublicID = nil
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

    @MainActor
    private func post() async {
        guard let originalImage = image else { return }
        isPosting = true
        errorMessage = nil
        defer { isPosting = false }

        do {
            // Bake the user's caption + location overlays at their committed
            // position and scale into the uploaded image. Pass an empty caption
            // string to Notion so StoryPlayerView's own caption overlay does
            // not double-render on top of the baked text. Location string stays
            // in Notion -- the player shows it in the metadata bar next to the
            // author, which sits at a different on-screen position than the
            // baked overlay, so the two don't visually conflict.
            let imageToUpload: UIImage = bakeOverlaysIntoImage() ?? originalImage

            // If a previous attempt uploaded successfully but Notion failed,
            // reuse the existing publicID instead of orphaning a fresh upload.
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
            // Full chain landed -- clear the publicID cache so a brand-new
            // compose session starts fresh.
            lastUploadedPublicID = nil

            // Push body still uses the typed caption (or location, or fallback)
            // since the recipient sees the push BEFORE the photo loads.
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

    /// Render the photo + draggable overlays into a single UIImage at upload
    /// time. Uses ImageRenderer (iOS 16+) so the SwiftUI preview maps 1:1 onto
    /// the baked output -- gesture state is the source of truth, no manual
    /// CoreGraphics math required. Renders at 3x scale for retina fidelity;
    /// Cloudinary handles per-display downsizing on serve.
    @MainActor
    private func bakeOverlaysIntoImage() -> UIImage? {
        guard let originalImage = image else { return nil }
        let displayWidth = UIScreen.main.bounds.width - 40
        let displayHeight = Self.composedPhotoHeight

        let composed = ZStack {
            Image(uiImage: originalImage)
                .resizable()
                .scaledToFill()
                .frame(width: displayWidth, height: displayHeight)
                .clipped()

            if !caption.isEmpty {
                Text(caption)
                    .font(.system(.body, design: .serif, weight: .medium))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.45))
                    .clipShape(Capsule())
                    .scaleEffect(captionScale)
                    .offset(x: captionOffset.width, y: captionOffset.height)
            }

            if !location.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "mappin.and.ellipse")
                    Text(location)
                }
                .font(.system(.subheadline, design: .serif, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.45))
                .clipShape(Capsule())
                .scaleEffect(locationScale)
                .offset(x: locationOffset.width, y: locationOffset.height)
            }
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
