import SwiftUI

struct GalleryView: View {
    @State private var photos: [DinosaurPhoto] = []
    @State private var isLoading = true
    @State private var selectedPhoto: DinosaurPhoto?
    @State private var showAddDino = false
    @State private var showBulkImport = false
    @State private var errorMessage: String?

    private let columns = [GridItem(.flexible(), spacing: 4), GridItem(.flexible(), spacing: 4)]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.sunBackground.ignoresSafeArea()

                if isLoading {
                    LoadingView()
                } else if photos.isEmpty {
                    EmptyStateView(
                        systemImage: "photo.badge.plus",
                        title: "No dinosaurs yet",
                        subtitle: "Add your first dino photo to start the collection!"
                    )
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 4) {
                            ForEach(photos) { photo in
                                GalleryCell(photo: photo)
                                    .onTapGesture { selectedPhoto = photo }
                                    .onLongPressGesture {
                                        toggleFavorite(photo)
                                    }
                            }
                        }
                        .padding(4)
                    }
                    .refreshable { await loadPhotos(force: true) }
                }

                // FABs
                VStack {
                    Spacer()
                    HStack {
                        // Bulk import button
                        Button {
                            showBulkImport = true
                        } label: {
                            Image(systemName: "photo.stack.fill")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(Color.sunAccent)
                                .frame(width: 48, height: 48)
                                .background(Color.sunSurface)
                                .clipShape(Circle())
                                .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
                        }
                        .padding(.leading, 20)

                        Spacer()

                        // Single add button
                        Button {
                            showAddDino = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(Color.sunBackground)
                                .frame(width: 56, height: 56)
                                .background(Color.sunAccent)
                                .clipShape(Circle())
                                .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
                        }
                        .padding(.trailing, 20)
                    }
                    .padding(.bottom, 8)
                }
            }
            .navigationTitle("Gallery")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Color.sunBackground, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .sheet(item: $selectedPhoto) { photo in
            DinoDetailView(photo: photo, onFavoriteToggle: { toggleFavorite($0) }, onEdit: { updated in
                if let idx = photos.firstIndex(where: { $0.id == updated.id }) {
                    photos[idx] = updated
                }
            })
        }
        .sheet(isPresented: $showAddDino) {
            AddDinoView { newPhoto in
                photos.insert(newPhoto, at: 0)
            }
        }
        .sheet(isPresented: $showBulkImport) {
            BulkImportView { newPhotos in
                photos.insert(contentsOf: newPhotos.reversed(), at: 0)
            }
        }
        .task { await loadPhotos() }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func loadPhotos(force: Bool = false) async {
        isLoading = true
        defer { isLoading = false }
        do {
            photos = try await NotionService.shared.fetchDinosaurs(force: force)
        } catch is CancellationError {
            return
        } catch let urlErr as URLError where urlErr.code == .cancelled {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func toggleFavorite(_ photo: DinosaurPhoto) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        guard let idx = photos.firstIndex(where: { $0.id == photo.id }) else { return }
        let newValue = !photos[idx].isFavorite
        photos[idx].isFavorite = newValue
        Task {
            try? await NotionService.shared.toggleFavorite(pageID: photo.id, isFavorite: newValue)
        }
    }
}

// MARK: - Gallery Cell
private struct GalleryCell: View {
    let photo: DinosaurPhoto

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay(
                    AsyncImageView(urlString: photo.cloudinaryURL, cornerRadius: 8)
                        .scaledToFill()
                        .clipped()
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))

            if photo.isFavorite {
                Image(systemName: "star.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.sunAccent)
                    .padding(6)
                    .background(.ultraThinMaterial, in: Circle())
                    .padding(6)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
