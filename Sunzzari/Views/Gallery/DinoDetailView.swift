import SwiftUI

struct DinoDetailView: View {
    let photo: DinosaurPhoto
    let onFavoriteToggle: (DinosaurPhoto) -> Void
    var onEdit: ((DinosaurPhoto) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var showEditDino = false
    @State private var isLoadingShare = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.sunBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 0) {
                        // Full-width photo
                        AsyncImageView(urlString: photo.cloudinaryURL ?? "", cornerRadius: 0)
                            .frame(maxWidth: .infinity)
                            .frame(height: 380)
                            .clipped()

                        // Info panel
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Text(photo.name)
                                    .font(.title2.weight(.bold))
                                    .foregroundStyle(Color.sunText)
                                Spacer()
                                Button {
                                    onFavoriteToggle(photo)
                                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                } label: {
                                    Image(systemName: photo.isFavorite ? "star.fill" : "star")
                                        .font(.title2)
                                        .foregroundStyle(Color.sunAccent)
                                        .animation(.spring(duration: 0.3), value: photo.isFavorite)
                                }
                            }

                            if let date = photo.dateAdded {
                                Label(date.formatted(date: .long, time: .omitted), systemImage: "calendar")
                                    .font(.subheadline)
                                    .foregroundStyle(Color.sunSecondary)
                            }

                            if !photo.tags.isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(photo.tags, id: \.self) { tag in
                                            HStack(spacing: 4) {
                                                Text(tag.emoji)
                                                Text(tag.rawValue)
                                            }
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(Color(hex: tag.color))
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 5)
                                            .background(Color(hex: tag.color).opacity(0.15))
                                            .clipShape(Capsule())
                                        }
                                    }
                                }
                            }
                        }
                        .padding(20)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showEditDino = true
                    } label: {
                        Image(systemName: "pencil")
                            .foregroundStyle(Color.sunAccent)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 16) {
                        Button {
                            Task { await shareImage() }
                        } label: {
                            if isLoadingShare {
                                ProgressView().tint(Color.sunAccent)
                            } else {
                                Image(systemName: "square.and.arrow.up")
                                    .foregroundStyle(Color.sunAccent)
                            }
                        }
                        Button("Done") { dismiss() }
                            .foregroundStyle(Color.sunAccent)
                    }
                }
            }
        }
        .sheet(isPresented: $showEditDino) {
            EditDinoView(photo: photo) { updated in
                onEdit?(updated)
                dismiss()
            }
        }
    }

    // MARK: - Share

    private func shareImage() async {
        isLoadingShare = true
        defer { isLoadingShare = false }
        guard let urlString = photo.cloudinaryURL, let url = URL(string: urlString),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let image = UIImage(data: data) else { return }
        await MainActor.run {
            let vc = UIActivityViewController(activityItems: [image], applicationActivities: nil)
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let root = windowScene.windows.first?.rootViewController else { return }
            var top = root
            while let presented = top.presentedViewController { top = presented }
            vc.popoverPresentationController?.sourceView = top.view
            top.present(vc, animated: true)
        }
    }
}
