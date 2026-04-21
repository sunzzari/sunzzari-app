import SwiftUI
import PhotosUI

struct BulkImportView: View {
    let onComplete: ([DinosaurPhoto]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var uploadStates: [UploadState] = []
    @State private var isUploading = false
    @State private var isDone = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.sunBackground.ignoresSafeArea()

                VStack(spacing: 24) {
                    if uploadStates.isEmpty {
                        // Picker prompt
                        VStack(spacing: 20) {
                            Spacer()
                            Image(systemName: "photo.stack.fill")
                                .font(.system(size: 64, design: .serif))
                                .foregroundStyle(Color.sunAccent)

                            Text("Select Photos")
                                .font(.title2.weight(.bold))
                                .foregroundStyle(Color.sunText)

                            Text("Choose as many dino photos as you want.\nThey'll all upload automatically.")
                                .font(.subheadline)
                                .foregroundStyle(Color.sunSecondary)
                                .multilineTextAlignment(.center)

                            PhotosPicker(
                                selection: $selectedItems,
                                maxSelectionCount: 100,
                                matching: .images
                            ) {
                                Label("Choose Photos", systemImage: "photo.on.rectangle.angled")
                                    .font(.headline)
                                    .foregroundStyle(Color.sunBackground)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.sunAccent)
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                                    .padding(.horizontal, 32)
                            }
                            .onChange(of: selectedItems) { _, items in
                                guard !items.isEmpty else { return }
                                uploadStates = items.map { UploadState(item: $0) }
                                Task { await uploadAll() }
                            }
                            Spacer()
                        }
                    } else {
                        // Progress list
                        ScrollView {
                            VStack(spacing: 0) {
                                // Summary header
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Uploading \(uploadStates.count) photos")
                                            .font(.headline)
                                            .foregroundStyle(Color.sunText)
                                        Text("\(doneCount) of \(uploadStates.count) complete")
                                            .font(.caption)
                                            .foregroundStyle(Color.sunSecondary)
                                    }
                                    Spacer()
                                    if isDone {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.green)
                                            .font(.title2)
                                    }
                                }
                                .padding(16)
                                .background(Color.sunSurface)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .padding(.horizontal, 16)
                                .padding(.top, 16)

                                // Progress bar
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(Color.sunSurface)
                                            .frame(height: 6)
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(Color.sunAccent)
                                            .frame(width: geo.size.width * progress, height: 6)
                                            .animation(.easeInOut, value: progress)
                                    }
                                }
                                .frame(height: 6)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)

                                // Per-photo status
                                LazyVStack(spacing: 8) {
                                    ForEach(uploadStates.indices, id: \.self) { i in
                                        UploadRow(state: uploadStates[i], index: i + 1)
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.bottom, 16)
                            }
                        }

                        if isDone {
                            Button {
                                let uploaded = uploadStates.compactMap(\.result)
                                onComplete(uploaded)
                                dismiss()
                            } label: {
                                Text("Done — View Gallery")
                                    .font(.headline)
                                    .foregroundStyle(Color.sunBackground)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.sunAccent)
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                                    .padding(.horizontal, 16)
                            }
                            .padding(.bottom, 8)
                        }
                    }
                }
            }
            .navigationTitle("Bulk Import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !isUploading {
                        Button("Cancel") { dismiss() }
                            .foregroundStyle(Color.sunSecondary)
                    }
                }
            }
        }
    }

    private var doneCount: Int {
        uploadStates.filter { $0.status == .done || $0.status == .failed }.count
    }

    private var progress: CGFloat {
        guard !uploadStates.isEmpty else { return 0 }
        return CGFloat(doneCount) / CGFloat(uploadStates.count)
    }

    private func uploadAll() async {
        isUploading = true
        // Upload concurrently in batches of 3
        let indices = uploadStates.indices
        await withTaskGroup(of: Void.self) { group in
            var active = 0
            for i in indices {
                if active >= 3 {
                    await group.next()
                    active -= 1
                }
                group.addTask { await self.uploadOne(index: i) }
                active += 1
            }
        }
        isUploading = false
        isDone = true
    }

    private func uploadOne(index: Int) async {
        await MainActor.run { uploadStates[index].status = .uploading }

        guard let data = try? await uploadStates[index].item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else {
            await MainActor.run { uploadStates[index].status = .failed }
            return
        }

        do {
            let url = try await CloudinaryService.shared.upload(image: image)
            let photo = DinosaurPhoto(
                id:            UUID().uuidString,
                name:          "Dino \(index + 1)",
                cloudinaryURL: url,
                dateAdded:     Date(),
                isFavorite:    false,
                tags:          []
            )
            try await NotionService.shared.createDinosaur(photo)
            await MainActor.run {
                uploadStates[index].status = .done
                uploadStates[index].result = photo
            }
        } catch {
            await MainActor.run { uploadStates[index].status = .failed }
        }
    }
}

// MARK: - Supporting types

struct UploadState {
    let item: PhotosPickerItem
    var status: Status = .pending
    var result: DinosaurPhoto? = nil

    enum Status: Equatable { case pending, uploading, done, failed }
}

private struct UploadRow: View {
    let state: UploadState
    let index: Int

    var body: some View {
        HStack(spacing: 12) {
            // Status icon
            Group {
                switch state.status {
                case .pending:
                    Image(systemName: "circle")
                        .foregroundStyle(Color.sunSecondary)
                case .uploading:
                    ProgressView().tint(.sunAccent).scaleEffect(0.8)
                case .done:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                case .failed:
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                }
            }
            .frame(width: 24)

            Text("Photo \(index)")
                .font(.subheadline)
                .foregroundStyle(Color.sunText)

            Spacer()

            Text(state.status.label)
                .font(.caption)
                .foregroundStyle(Color.sunSecondary)
        }
        .padding(12)
        .background(Color.sunSurface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private extension UploadState.Status {
    var label: String {
        switch self {
        case .pending:   return "Waiting"
        case .uploading: return "Uploading..."
        case .done:      return "Saved"
        case .failed:    return "Failed"
        }
    }
}
