import SwiftUI
import PhotosUI

struct WinePickerView: View {
    @Environment(\.dismiss) private var dismiss

    // MARK: - State

    private enum PickerStep { case landing, preview, loading, result, reading, tried }

    @State private var step: PickerStep = .landing
    @State private var selectedImage: UIImage?
    @State private var resultText: String = ""
    @State private var errorMessage: String?

    // What she wants from this pick ("a white", "by the glass only"). Kept across
    // "Try Another" so the next page of the same wine list needs no retyping.
    @State private var notes: String = ""
    @FocusState private var notesFocused: Bool

    // "Log one I tried": every wine read off the photo. nil until asked for, then kept
    // for this photo so going back and forth does not pay for a second read.
    @State private var seenWines: [AnthropicService.WineAutofill]?
    @State private var wineToLog: AnthropicService.WineAutofill?
    @State private var loggedIDs: Set<UUID> = []

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
                    case .reading:  loadingView
                    case .tried:    triedView
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
        .sheet(item: $wineToLog) { wine in
            AddWineView(prefill: wine) { loggedIDs.insert(wine.id) }
        }
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
                        .font(.system(.subheadline, design: .serif))
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
                        // minWidth 0: a wide photo otherwise stretches the whole column past the screen edges
                        .frame(minWidth: 0, maxWidth: .infinity)
                        .frame(height: 280)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .onTapGesture { notesFocused = false }
                }

                // Optional request for this pick
                VStack(alignment: .leading, spacing: 8) {
                    Text("Anything specific? (optional)")
                        .font(.system(.subheadline, design: .serif))
                        .foregroundStyle(Color.sunSecondary)
                    TextField("A white, a red, by the glass only...", text: $notes, axis: .vertical)
                        .font(.system(size: 16, design: .serif))
                        .lineLimit(1...3)
                        .focused($notesFocused)
                        .padding()
                        .background(Color.sunSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(Color.sunText)
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
                    seenWines = nil
                    step = .landing
                } label: {
                    Text("Choose a different photo")
                        .font(.system(.subheadline, design: .serif))
                        .foregroundStyle(Color.sunSecondary)
                }
            }
            .padding(24)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(1.6)
                .tint(Color.sunAccent)

            Text(step == .reading ? "Reading the wines in your photo…" : "Asking our sommelier…")
                .font(.system(.subheadline, design: .serif))
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
                                .font(.system(.caption, design: .serif, weight: .semibold))
                            Text("SOMMELIER PICK")
                                .font(.system(size: 11, weight: .semibold, design: .serif))
                                .tracking(1.2)
                        }
                        .foregroundStyle(Color.sunAccent)

                        Text(formattedResult)
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
                        Task { await readWines() }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "plus.circle")
                            Text("Log one I tried")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.sunSurface)
                        .foregroundStyle(Color.sunAccent)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }

                    Button {
                        selectedImage = nil
                        selectedItem = nil
                        seenWines = nil
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

    /// The sommelier writes **bold** and *italic* markers. Draw them as formatting, not as
    /// literal symbols; if the text cannot be parsed, show it as it came.
    private var formattedResult: AttributedString {
        (try? AttributedString(
            markdown: resultText,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(resultText)
    }

    // MARK: - Log one I tried

    private var triedView: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 6) {
                    Text("Which one did you try?")
                        .font(.system(size: 22, weight: .bold, design: .serif))
                        .foregroundStyle(Color.sunText)
                    Text("Tap a wine to add it to My Wine")
                        .font(.system(.subheadline, design: .serif))
                        .foregroundStyle(Color.sunSecondary)
                }
                .padding(.top, 8)

                let wines = seenWines ?? []
                if wines.isEmpty {
                    Text("No wines could be read from this photo. Try a closer, sharper photo.")
                        .font(.system(.subheadline, design: .serif))
                        .foregroundStyle(Color.sunSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.vertical, 24)
                } else {
                    VStack(spacing: 10) {
                        ForEach(wines) { wine in
                            Button { wineToLog = wine } label: { wineRow(wine) }
                        }
                    }
                }

                Button {
                    step = .result
                } label: {
                    Text("Back to the pick")
                        .font(.system(.subheadline, design: .serif))
                        .foregroundStyle(Color.sunSecondary)
                }
                .padding(.top, 8)
            }
            .padding(24)
        }
    }

    private func wineRow(_ wine: AnthropicService.WineAutofill) -> some View {
        let details = [wine.producer, wine.vintage.map(String.init) ?? "", wine.region, wine.wineType.rawValue]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")

        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(wine.wineName)
                    .font(.system(size: 16, weight: .bold, design: .serif))
                    .foregroundStyle(Color.sunText)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Text(details)
                    .font(.system(.subheadline, design: .serif))
                    .foregroundStyle(Color.sunSecondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                if let cost = wine.cost {
                    Text(cost, format: .currency(code: "USD").precision(.fractionLength(0...2)))
                        .font(.system(size: 15, weight: .semibold, design: .serif))
                        .foregroundStyle(Color.sunText)
                }
                if loggedIDs.contains(wine.id) {
                    Text("Added")
                        .font(.system(size: 12, weight: .semibold, design: .serif))
                        .foregroundStyle(Color.sunAccent)
                }
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold, design: .serif))
                .foregroundStyle(Color.sunSecondary)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .background(Color.sunSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Helpers

    @ViewBuilder
    private func photoButton(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(.title2, design: .serif))
                .foregroundStyle(Color.sunAccent)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .bold, design: .serif))
                    .foregroundStyle(Color.sunText)
                Text(subtitle)
                    .font(.system(.subheadline, design: .serif))
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
        notesFocused = false
        step = .loading
        do {
            let text = try await AnthropicService.shared.analyzeWineImage(image, notes: notes)
            resultText = text
            step = .result
        } catch {
            step = .preview
            errorMessage = error.localizedDescription
        }
    }

    private func readWines() async {
        guard let image = selectedImage else { return }
        if seenWines != nil {
            step = .tried
            return
        }
        step = .reading
        do {
            seenWines = try await AnthropicService.shared.listWines(in: image)
            step = .tried
        } catch {
            step = .result
            errorMessage = error.localizedDescription
        }
    }
}
