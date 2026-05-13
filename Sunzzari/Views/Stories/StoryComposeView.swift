import SwiftUI
import PhotosUI
import UIKit
import AVFoundation
import Combine

/// Instagram-style story compose. Opens directly into an embedded camera
/// (fullscreen live preview + shutter + library thumbnail + flip). After a
/// photo is captured or picked, the photo fills the screen and tapping it
/// opens an inline caption editor. The caption renders as a draggable pill
/// and is baked into the upload at post time.
struct StoryComposeView: View {
    @Environment(\.dismiss) private var dismiss
    let onPosted: (StoryPost) -> Void

    @State private var pickerItem: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var imageFromCamera = false
    @State private var caption: String = ""
    @State private var isPosting = false
    @State private var errorMessage: String?
    @State private var showLibrary = false

    // Caching the publicID lets a retry skip a second Cloudinary upload if
    // the first succeeded but Notion createStoryPost failed.
    @State private var lastUploadedPublicID: String?

    // Caption editor state. Drag offsets clamped on release so the pill
    // can't escape the visible photo area.
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
                CameraCaptureView(
                    onCapture: { captured in
                        self.image = captured
                        self.imageFromCamera = true
                        self.errorMessage = nil
                    },
                    onPickFromLibrary: { showLibrary = true },
                    onClose: { dismiss() }
                )
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
        .photosPicker(isPresented: $showLibrary, selection: $pickerItem, matching: .images)
        .onChange(of: pickerItem) { _, newItem in
            Task { await loadPicked(newItem) }
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
                    .blur(radius: 32)
                    .overlay(Color.black.opacity(0.15))

                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: imageFromCamera ? .fill : .fit)
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
                        // Discard the captured image, return to embedded camera.
                        self.image = nil
                        self.imageFromCamera = false
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

    private func loadPicked(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        do {
            if let data = try await item.loadTransferable(type: Data.self),
               let img = UIImage(data: data) {
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
                .blur(radius: 32)
                .overlay(Color.black.opacity(0.15))

            Image(uiImage: originalImage)
                .resizable()
                .aspectRatio(contentMode: imageFromCamera ? .fill : .fit)
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

// MARK: - Embedded camera

/// Instagram-style in-app camera. Renders a fullscreen AVCaptureSession live
/// preview with a shutter button, library thumbnail, flip-camera button,
/// and close (X). Handles video permission and gracefully falls back to the
/// library-only UI when access is denied or the device has no camera.
struct CameraCaptureView: View {
    let onCapture: (UIImage) -> Void
    let onPickFromLibrary: () -> Void
    let onClose: () -> Void

    @StateObject private var model = CameraCaptureModel()

    // Pinch-zoom state. `baseZoom` is the device's videoZoomFactor at the
    // start of the gesture; MagnificationGesture multiplies it on .onChanged
    // and we commit back to base on .onEnded.
    @State private var baseZoom: CGFloat = 1.0
    @State private var currentZoom: CGFloat = 1.0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if model.permissionGranted {
                CameraPreviewLayer(session: model.session)
                    .ignoresSafeArea()
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                let target = baseZoom * value
                                currentZoom = model.setZoom(target)
                            }
                            .onEnded { _ in
                                baseZoom = currentZoom
                            }
                    )

                if currentZoom > 1.05 {
                    Text(String(format: "%.1fx", currentZoom))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 130)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .allowsHitTesting(false)
                }
            } else if model.permissionDenied {
                permissionDeniedView
            }

            VStack {
                topRow
                Spacer()
                bottomRow
            }
        }
        .task { await model.setup() }
        .onDisappear { model.teardown() }
        .onChange(of: model.capturedImage) { _, newValue in
            if let img = newValue {
                // Crop to the screen aspect so what was visible in the preview
                // is exactly what shows up in compose — AVCaptureSession ships
                // the full 4:3 sensor, but the preview was .resizeAspectFill,
                // so the user only ever saw the cropped portion.
                let cropped = img.croppedToAspectRatio(of: UIScreen.main.bounds.size)
                onCapture(cropped)
                model.capturedImage = nil
            }
        }
    }

    private var topRow: some View {
        HStack {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(.ultraThinMaterial, in: Circle())
            }
            Spacer()
            if model.permissionGranted {
                Button {
                    model.flipCamera()
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath.camera")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(10)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .accessibilityLabel("Flip camera")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var bottomRow: some View {
        HStack {
            // Library thumbnail (left)
            Button(action: onPickFromLibrary) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.ultraThinMaterial)
                        .frame(width: 44, height: 44)
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.3), lineWidth: 0.5))
            }
            .accessibilityLabel("Choose from library")

            Spacer()

            // Shutter (center)
            if model.permissionGranted {
                Button {
                    model.capture()
                } label: {
                    ZStack {
                        Circle()
                            .stroke(Color.white, lineWidth: 4)
                            .frame(width: 76, height: 76)
                        Circle()
                            .fill(Color.white)
                            .frame(width: 62, height: 62)
                    }
                }
                .accessibilityLabel("Take photo")
            } else {
                Spacer().frame(width: 76, height: 76)
            }

            Spacer()

            // Symmetry placeholder (right) — keeps the shutter visually centered.
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 36)
    }

    private var permissionDeniedView: some View {
        VStack(spacing: 14) {
            Image(systemName: "camera.fill")
                .font(.system(size: 44, design: .serif))
                .foregroundStyle(.white.opacity(0.7))
            Text("Camera access needed")
                .font(.system(.headline, design: .serif))
                .foregroundStyle(.white)
            Text("Enable Camera in Settings to take a photo, or pick one from your library.")
                .font(.system(.footnote, design: .serif))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.sunAccent)
            .padding(.top, 4)
        }
    }
}

/// AVCaptureSession-backed model. Session work happens on a private serial
/// queue (per Apple's guidance); only `@Published` writes are dispatched
/// back to MainActor.
@MainActor
final class CameraCaptureModel: NSObject, ObservableObject {
    let session = AVCaptureSession()
    @Published var permissionGranted = false
    @Published var permissionDenied = false
    @Published var capturedImage: UIImage?

    private let sessionQueue = DispatchQueue(label: "sunzzari.camera.session")
    private let photoOutput = AVCapturePhotoOutput()
    private var videoInput: AVCaptureDeviceInput?
    private var position: AVCaptureDevice.Position = .back

    func setup() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            permissionGranted = true
            configureSession()
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            permissionGranted = granted
            permissionDenied = !granted
            if granted { configureSession() }
        case .denied, .restricted:
            permissionDenied = true
        @unknown default:
            permissionDenied = true
        }
    }

    func teardown() {
        sessionQueue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    func capture() {
        let settings = AVCapturePhotoSettings()
        settings.flashMode = .off
        sessionQueue.async { [photoOutput, weak self] in
            guard let self else { return }
            photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    /// Apply a pinch-driven zoom factor to the active camera device. Returns
    /// the clamped value so the UI can show "1.5x" etc. without recomputing
    /// the device's max zoom on every drag tick.
    @discardableResult
    func setZoom(_ factor: CGFloat) -> CGFloat {
        guard let device = videoInput?.device else { return 1.0 }
        let maxFactor = min(device.activeFormat.videoMaxZoomFactor, 10.0)
        let clamped = max(1.0, min(maxFactor, factor))
        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = clamped
            device.unlockForConfiguration()
        } catch {
            return device.videoZoomFactor
        }
        return clamped
    }

    func flipCamera() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()
            defer { self.session.commitConfiguration() }
            if let current = self.videoInput {
                self.session.removeInput(current)
            }
            let newPosition: AVCaptureDevice.Position = (self.position == .back) ? .front : .back
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: newPosition),
                  let input = try? AVCaptureDeviceInput(device: device),
                  self.session.canAddInput(input) else {
                // Revert: re-add previous input if available
                if let prev = self.videoInput, self.session.canAddInput(prev) {
                    self.session.addInput(prev)
                }
                return
            }
            self.session.addInput(input)
            self.videoInput = input
            self.position = newPosition
        }
    }

    private func configureSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()
            self.session.sessionPreset = .photo

            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: self.position),
                  let input = try? AVCaptureDeviceInput(device: device),
                  self.session.canAddInput(input) else {
                self.session.commitConfiguration()
                return
            }
            self.session.addInput(input)
            self.videoInput = input

            if self.session.canAddOutput(self.photoOutput) {
                self.session.addOutput(self.photoOutput)
            }
            self.session.commitConfiguration()
            self.session.startRunning()
        }
    }
}

extension CameraCaptureModel: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil,
              let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else { return }
        let oriented = image.normalized()
        Task { @MainActor in
            self.capturedImage = oriented
        }
    }
}

/// UIView wrapper around AVCaptureVideoPreviewLayer. SwiftUI doesn't expose
/// the layer-backed preview directly, so we drop down to UIKit.
struct CameraPreviewLayer: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {}

    final class PreviewUIView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoPreviewLayer: AVCaptureVideoPreviewLayer {
            // swiftlint:disable:next force_cast
            layer as! AVCaptureVideoPreviewLayer
        }
    }
}

extension UIImage {
    /// Center-crop the image to match the aspect ratio of `target`. The
    /// AVCaptureSession ships a full 4:3 sensor frame but the preview uses
    /// `.resizeAspectFill`, so the user only ever saw the screen-shaped
    /// crop. Re-cropping to screen aspect here makes the captured photo
    /// match what was in the viewfinder.
    func croppedToAspectRatio(of target: CGSize) -> UIImage {
        guard let cg = cgImage, target.width > 0, target.height > 0 else { return self }
        let pixelWidth = CGFloat(cg.width)
        let pixelHeight = CGFloat(cg.height)
        let targetAR = target.width / target.height
        let imageAR = pixelWidth / pixelHeight
        let cropPixelRect: CGRect
        if imageAR > targetAR {
            let newWidth = pixelHeight * targetAR
            let x = (pixelWidth - newWidth) / 2
            cropPixelRect = CGRect(x: x, y: 0, width: newWidth, height: pixelHeight)
        } else {
            let newHeight = pixelWidth / targetAR
            let y = (pixelHeight - newHeight) / 2
            cropPixelRect = CGRect(x: 0, y: y, width: pixelWidth, height: newHeight)
        }
        guard let cropped = cg.cropping(to: cropPixelRect) else { return self }
        return UIImage(cgImage: cropped, scale: scale, orientation: .up)
    }
}

private extension UIImage {
    /// Re-render with `.up` orientation baked into pixels so downstream code
    /// (Cloudinary, ImageRenderer) doesn't have to track EXIF orientation.
    func normalized() -> UIImage {
        if imageOrientation == .up { return self }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
