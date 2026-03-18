import SwiftUI
import PhotosUI

struct AddWineView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var wineName = ""
    @State private var wineType: Wine.WineType = .red
    @State private var producer = ""
    @State private var vintageText = ""
    @State private var region = ""
    @State private var purchaseLocation: Wine.PurchaseLocation? = nil
    @State private var costText = ""
    @State private var rating: Wine.Rating? = nil
    @State private var useForCooking = false
    @State private var notes = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    // AI autofill
    @State private var showSourceDialog = false
    @State private var showCamera = false
    @State private var pickerItem: PhotosPickerItem? = nil
    @State private var showPhotoPicker = false
    @State private var isAILoading = false
    @State private var aiMessage: String? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                Color.sunBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {

                        aiAutofillSection

                        formField(label: "Wine Name", icon: "wineglass") {
                            TextField("e.g. Gevrey-Chambertin 1er Cru", text: $wineName)
                                .padding()
                                .background(Color.sunSurface)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .foregroundStyle(Color.sunText)
                        }

                        formField(label: "Wine Type", icon: "drop") {
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
                                ForEach(Wine.WineType.allCases, id: \.self) { type in
                                    Button {
                                        wineType = type
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    } label: {
                                        Text(type.rawValue)
                                            .font(.system(size: 13, weight: .semibold))
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 10)
                                            .background(
                                                wineType == type
                                                    ? Color(hex: type.colorHex).opacity(0.25)
                                                    : Color.sunSurface
                                            )
                                            .foregroundStyle(
                                                wineType == type
                                                    ? Color(hex: type.colorHex)
                                                    : Color.sunSecondary
                                            )
                                            .clipShape(RoundedRectangle(cornerRadius: 10))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 10)
                                                    .strokeBorder(
                                                        wineType == type ? Color(hex: type.colorHex) : Color.clear,
                                                        lineWidth: 1.5
                                                    )
                                            )
                                    }
                                }
                            }
                        }

                        formField(label: "Producer (optional)", icon: "building.columns") {
                            TextField("Producer or winery", text: $producer)
                                .padding()
                                .background(Color.sunSurface)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .foregroundStyle(Color.sunText)
                        }

                        HStack(spacing: 12) {
                            formField(label: "Vintage (optional)", icon: "calendar") {
                                TextField("e.g. 2019", text: $vintageText)
                                    .keyboardType(.numberPad)
                                    .padding()
                                    .background(Color.sunSurface)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .foregroundStyle(Color.sunText)
                            }
                            formField(label: "Cost (optional)", icon: "dollarsign") {
                                TextField("0.00", text: $costText)
                                    .keyboardType(.decimalPad)
                                    .padding()
                                    .background(Color.sunSurface)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .foregroundStyle(Color.sunText)
                            }
                        }

                        formField(label: "Region (optional)", icon: "map") {
                            TextField("e.g. Burgundy, Tuscany", text: $region)
                                .padding()
                                .background(Color.sunSurface)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .foregroundStyle(Color.sunText)
                        }

                        formField(label: "Purchase Location (optional)", icon: "cart") {
                            Picker("Purchase Location", selection: $purchaseLocation) {
                                Text("None").tag(Optional<Wine.PurchaseLocation>.none)
                                ForEach(Wine.PurchaseLocation.allCases, id: \.self) { loc in
                                    Text(loc.rawValue).tag(Optional(loc))
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(Color.sunAccent)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(Color.sunSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }

                        formField(label: "Rating (optional)", icon: "star") {
                            HStack(spacing: 10) {
                                ForEach(Wine.Rating.allCases, id: \.self) { r in
                                    Button {
                                        rating = rating == r ? nil : r
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    } label: {
                                        Text(String(repeating: "⭐", count: r.stars))
                                            .font(.system(size: 14))
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 6)
                                            .background(
                                                rating == r
                                                    ? Color.sunAccent.opacity(0.2)
                                                    : Color.sunSurface
                                            )
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                    }
                                }
                            }
                        }

                        formField(label: "Use for Cooking", icon: "flame") {
                            Toggle("", isOn: $useForCooking)
                                .tint(.sunAccent)
                                .padding()
                                .background(Color.sunSurface)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }

                        formField(label: "Notes (optional)", icon: "note.text") {
                            TextField("Tasting notes, food pairing...", text: $notes, axis: .vertical)
                                .lineLimit(3...5)
                                .padding()
                                .background(Color.sunSurface)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .foregroundStyle(Color.sunText)
                        }

                        if let errorMessage {
                            Text(errorMessage).font(.caption).foregroundStyle(.red)
                        }

                        Button { Task { await save() } } label: {
                            HStack(spacing: 10) {
                                if isSaving { ProgressView().tint(.sunBackground) }
                                Text(isSaving ? "Saving..." : "Save Wine")
                                    .font(.headline)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(wineName.isEmpty ? Color.sunSurface : Color.sunAccent)
                            .foregroundStyle(wineName.isEmpty ? Color.sunSecondary : Color.sunBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .disabled(wineName.isEmpty || isSaving)
                    }
                    .padding(20)
                }
            }
            .navigationTitle("New Wine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Color.sunSecondary)
                }
            }
        }
        .confirmationDialog("Add Photo", isPresented: $showSourceDialog) {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button("Take Photo") { showCamera = true }
            }
            Button("Choose from Library") { showPhotoPicker = true }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showCamera) {
            CameraPickerView { image in Task { await autofillFromImage(image) } }
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $pickerItem, matching: .images)
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else { return }
                pickerItem = nil
                await autofillFromImage(image)
            }
        }
    }

    // MARK: - AI Autofill Section

    private var aiAutofillSection: some View {
        VStack(spacing: 10) {
            if isAILoading {
                HStack(spacing: 10) {
                    ProgressView().tint(Color.sunAccent)
                    Text("Claude is reading the label...")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.sunSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color.sunSurface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                Button { showSourceDialog = true } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 15, weight: .semibold))
                        Text("Autofill from Photo")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.sunAccent.opacity(0.12))
                    .foregroundStyle(Color.sunAccent)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.sunAccent.opacity(0.4), lineWidth: 1))
                }
            }

            if let msg = aiMessage {
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(msg.hasPrefix("✓") ? Color.green : Color.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Color.white.opacity(0.15).frame(height: 0.5)
                Text("or fill manually")
                    .font(.caption)
                    .foregroundStyle(Color.sunSecondary)
                    .fixedSize()
                    .padding(.horizontal, 8)
                Color.white.opacity(0.15).frame(height: 0.5)
            }
        }
    }

    // MARK: - AI Logic

    private func autofillFromImage(_ image: UIImage) async {
        isAILoading = true
        aiMessage = nil
        defer { isAILoading = false }
        do {
            let info = try await AnthropicService.shared.extractWineInfo(from: image)
            if !info.wineName.isEmpty { wineName = info.wineName }
            if !info.producer.isEmpty { producer = info.producer }
            if let v = info.vintage { vintageText = String(v) }
            if !info.region.isEmpty { region = info.region }
            wineType = info.wineType
            if !info.notes.isEmpty { notes = info.notes }
            aiMessage = "✓ Label scanned — review and adjust before saving"
        } catch {
            aiMessage = "Could not read label: \(error.localizedDescription)"
        }
    }

    // MARK: - Helpers

    private func formField<C: View>(label: String, icon: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(label, systemImage: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.sunSecondary)
            content()
        }
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            let w = Wine(
                id:              UUID().uuidString,
                wineName:        wineName,
                producer:        producer,
                vintage:         Int(vintageText),
                region:          region,
                wineType:        wineType,
                purchaseLocation: purchaseLocation,
                cost:            Double(costText),
                rating:          rating,
                notes:           notes,
                useForCooking:   useForCooking
            )
            try await NotionService.shared.createWine(w)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            NotionService.shared.invalidateWines()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Camera Picker

private struct CameraPickerView: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let vc = UIImagePickerController()
        vc.sourceType = .camera
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPickerView
        init(_ parent: CameraPickerView) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onImage(image) }
            picker.dismiss(animated: true)
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}
