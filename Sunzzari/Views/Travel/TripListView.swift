import SwiftUI

struct TripListView: View {
    @State private var trips: [Trip] = []
    @State private var isLoading = true
    @State private var isOffline = false

    private let columns = [GridItem(.adaptive(minimum: 340), spacing: 16)]

    private let gradients: [LinearGradient] = [
        LinearGradient(colors: [Color(hex: "#1E3A5F"), Color(hex: "#0F1B2D")], startPoint: .topLeading, endPoint: .bottomTrailing),
        LinearGradient(colors: [Color(hex: "#2D1B4E"), Color(hex: "#1A0F2E")], startPoint: .topLeading, endPoint: .bottomTrailing),
        LinearGradient(colors: [Color(hex: "#1B3D2F"), Color(hex: "#0F2318")], startPoint: .topLeading, endPoint: .bottomTrailing),
        LinearGradient(colors: [Color(hex: "#3D2B1B"), Color(hex: "#231A0F")], startPoint: .topLeading, endPoint: .bottomTrailing),
    ]

    var body: some View {
        ZStack {
            Color.sunBackground.ignoresSafeArea()

            if isLoading && trips.isEmpty {
                VStack(spacing: 16) {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.sunSurface)
                            .frame(height: 200)
                    }
                }
                .padding()
                .redacted(reason: .placeholder)
            } else {
                ScrollView {
                    if isOffline {
                        offlineBanner
                    }

                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(trips) { trip in
                            NavigationLink(value: trip.id) {
                                TripCard(trip: trip, gradient: gradients[abs(trip.id.hashValue) % gradients.count])
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
                .refreshable {
                    await loadTrips(force: true)
                }
            }
        }
        .navigationTitle("Travel")
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(Color.sunSurface, for: .navigationBar)
        .navigationDestination(for: String.self) { tripId in
            if let trip = trips.first(where: { $0.id == tripId }) {
                TripDetailView(trip: trip)
            }
        }
        .task {
            await loadTrips()
        }
    }

    private var offlineBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash")
            Text("Viewing cached data")
        }
        .font(.caption)
        .foregroundStyle(Color.sunBackground)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.sunAccent)
        .clipShape(Capsule())
        .padding(.top, 4)
    }

    private func loadTrips(force: Bool = false) async {
        // Show cached data immediately while network loads
        if trips.isEmpty, let cached = TravelService.shared.tripsDiskCache() {
            trips = cached
            isOffline = true
        }
        if trips.isEmpty { isLoading = true }
        do {
            trips = try await TravelService.shared.fetchTrips(force: force)
            isOffline = TravelService.shared.isOffline
        } catch is CancellationError {
            return
        } catch let urlErr as URLError where urlErr.code == .cancelled {
            return
        } catch {
            if trips.isEmpty, let cached = TravelService.shared.tripsDiskCache() {
                trips = cached
                isOffline = true
            }
        }
        isLoading = false
    }
}

// MARK: - Trip Card

private struct TripCard: View {
    let trip: Trip
    let gradient: LinearGradient

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Cover image or gradient fallback
            if let urlStr = trip.coverImageURL, let url = URL(string: urlStr) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                    default:
                        gradient
                    }
                }
            } else {
                gradient
            }
        }
        .frame(height: 200)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(alignment: .bottomLeading) {
            // Dark gradient overlay for text readability
            VStack(alignment: .leading, spacing: 6) {
                Spacer()

                // Status badge
                if let status = trip.status {
                    Text(status.rawValue)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color(hex: status.colorHex))
                        .clipShape(Capsule())
                }

                // Trip name
                Text(trip.name)
                    .font(.title3.weight(.bold))
                    .fontDesign(.serif)
                    .foregroundStyle(.white)
                    .lineLimit(2)

                // Location + dates
                HStack(spacing: 8) {
                    if !trip.location.isEmpty {
                        Text(trip.location)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    if !trip.dateRangeDisplay.isEmpty {
                        Text(trip.dateRangeDisplay)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [.clear, .black.opacity(0.7)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }
}
