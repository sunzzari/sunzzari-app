import SwiftUI
import PhotosUI

struct WinePickerView: View {
    @Environment(\.dismiss) private var dismiss

    // MARK: - State

    private enum PickerStep { case landing, preview, loading, result }

    @State private var step: PickerStep = .landing
    @State private var selectedImage: UIImage?
    @State private var resultText: String = ""
    @State private var errorMessage: String?

    // Photo library
    @State private var selectedItem: PhotosPickerItem?
    // Camera sheet
    @State private var showCamera = false
    @State private var cameraImage: UIImage?

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                Color.sunBackground.ignoresSafeArea()

                Group {
                    switch step {
                    case .landing:  landingView
                    case .preview:  previewView
                    case .loading:  loadingView
                    case .result:   resultView
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: step)
            }
            .navigationTitle("Wine Picker")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.sunSecondary)
                }
            }
            .alert("Sommelier Error", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
        // Camera sheet (fullscreen cover — UIImagePickerController requirement)
        .fullScreenCover(isPresented: $showCamera) {
            CameraCapture(image: $cameraImage)
                .ignoresSafeArea()
        }
        .onChange(of: cameraImage) { _, newImage in
            guard let img = newImage else { return }
            selectedImage = img
            cameraImage = nil
            step = .preview
        }
        .onChange(of: selectedItem) { _, newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    selectedImage = image
                    step = .preview
                }
            }
        }
    }

    // MARK: - Landing

    private var landingView: some View {
        ScrollView {
            VStack(spacing: 32) {

                // Header
                VStack(spacing: 8) {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 48, design: .serif))
                        .foregroundStyle(Color.sunAccent)
                    Text("Wine Picker")
                        .font(.system(size: 28, weight: .bold, design: .serif))
                        .foregroundStyle(Color.sunText)
                    Text("Snap a shelf or menu and we'll pick")
                        .font(.subheadline)
                        .foregroundStyle(Color.sunSecondary)
                }
                .padding(.top, 24)

                // Photo buttons
                VStack(spacing: 12) {
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button {
                            showCamera = true
                        } label: {
                            photoButton(
                                icon: "camera.fill",
                                title: "Take a Photo",
                                subtitle: "Point at a shelf or list"
                            )
                        }
                    }

                    PhotosPicker(selection: $selectedItem, matching: .images) {
                        photoButton(
                            icon: "photo.on.rectangle",
                            title: "Choose from Library",
                            subtitle: "Pick an existing photo"
                        )
                    }
                }
            }
            .padding(24)
        }
    }

    // MARK: - Preview

    private var previewView: some View {
        ScrollView {
            VStack(spacing: 24) {
                if let image = selectedImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 280)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }

                // Primary CTA
                Button {
                    Task { await analyze() }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "wand.and.stars")
                        Text("Pick for us")
                            .fontWeight(.bold)
                        Image(systemName: "arrow.right")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.sunAccent)
                    .foregroundStyle(Color.sunBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }

                // Secondary: change photo
                Button {
                    selectedImage = nil
                    selectedItem = nil
                    step = .landing
                } label: {
                    Text("Choose a different photo")
                        .font(.subheadline)
                        .foregroundStyle(Color.sunSecondary)
                }
            }
            .padding(24)
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(1.6)
                .tint(Color.sunAccent)

            Text("Asking our sommelier…")
                .font(.subheadline)
                .foregroundStyle(Color.sunSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Result

    private var resultView: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Result card — gold accent bar left edge, same as BestOfEntryCard
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(Color.sunAccent)
                        .frame(width: 3)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "wineglass")
                                .font(.caption.weight(.semibold))
                            Text("SOMMELIER PICK")
                                .font(.system(size: 11, weight: .semibold, design: .serif))
                                .tracking(1.2)
                        }
                        .foregroundStyle(Color.sunAccent)

                        Text(resultText)
                            .font(.system(size: 15, design: .serif))
                            .foregroundStyle(Color.sunText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(16)
                }
                .background(Color.sunSurface)
                .clipShape(RoundedRectangle(cornerRadius: 16))

                // Action buttons
                VStack(spacing: 12) {
                    Button {
                        selectedImage = nil
                        selectedItem = nil
                        resultText = ""
                        step = .landing
                    } label: {
                        Text("Try Another")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.sunSurface)
                            .foregroundStyle(Color.sunText)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }

                    Button {
                        dismiss()
                    } label: {
                        Text("Done")
                            .fontWeight(.bold)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.sunAccent)
                            .foregroundStyle(Color.sunBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }
            }
            .padding(24)
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func photoButton(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(Color.sunAccent)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .bold, design: .serif))
                    .foregroundStyle(Color.sunText)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(Color.sunSecondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold, design: .serif))
                .foregroundStyle(Color.sunSecondary)
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 20)
        .background(Color.sunSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Actions

    private func analyze() async {
        guard let image = selectedImage else { return }
        step = .loading
        do {
            let text = try await AnthropicService.shared.analyzeWineImage(image)
            resultText = text
            step = .result
        } catch {
            step = .preview
            errorMessage = error.localizedDescription
        }
    }
}
