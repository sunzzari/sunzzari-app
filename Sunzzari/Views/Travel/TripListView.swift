import SwiftUI

struct TripListView: View {
    @State private var trips: [Trip] = []
    @State private var isLoading = true
    @State private var isOffline = false
    @State private var loadErrorMessage: String?
    @State private var showCompleted = false

    private var visibleTrips: [Trip] {
        showCompleted ? trips : trips.filter { $0.status != .completed }
    }

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

            VStack(spacing: 0) {
                SerifNavHeader("Travel") {
                    Menu {
                        Toggle("Show completed", isOn: $showCompleted)
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .foregroundStyle(Color.sunAccent)
                    }
                }

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
                } else if trips.isEmpty, let message = loadErrorMessage {
                    loadErrorState(message)
                } else {
                    ScrollView {
                        if isOffline {
                            offlineBanner
                        }

                        // The trip she is on (or about to be on) goes above the
                        // grid. Hunting for it among cards is the problem this
                        // whole screen family is fixing.
                        if let featured = trips.first(where: { $0.isLiveToday })
                            ?? trips.filter({ $0.hasNotStarted })
                                .sorted(by: { ($0.departureDate ?? "") < ($1.departureDate ?? "") }).first {
                            NavigationLink { TripTodayView(trip: featured) } label: {
                                featuredCard(featured)
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal)
                            .padding(.top, 4)
                        }

                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(visibleTrips) { trip in
                                NavigationLink(destination: TripDetailView(trip: trip)) {
                                    TripCard(trip: trip, gradient: gradients[stableGradientIndex(trip.id)])
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
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await loadTrips()
        }
    }

    private func featuredCard(_ trip: Trip) -> some View {
        HStack(spacing: 12) {
            Image(systemName: trip.isLiveToday ? "suitcase.rolling.fill" : "calendar")
                .font(.system(size: 18))
                .foregroundStyle(Color.sunBackground)
                .frame(width: 38, height: 38)
                .background(Color.sunAccent)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(trip.isLiveToday ? "ON THIS TRIP NOW" : "UP NEXT")
                    .font(.system(size: 10, weight: .semibold, design: .serif))
                    .foregroundStyle(Color.sunAccent)
                Text(trip.name)
                    .font(.system(size: 17, weight: .bold, design: .serif))
                    .foregroundStyle(Color.sunText)
                    .multilineTextAlignment(.leading)
                Text(trip.isLiveToday ? "Open today's plan" : "Open the day-by-day plan")
                    .font(.system(.caption, design: .serif))
                    .foregroundStyle(Color.sunSecondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.sunAccent)
        }
        .padding(12)
        .background(Color.sunAccent.opacity(0.12))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.sunAccent.opacity(0.3), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var offlineBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash")
            Text("Viewing cached data")
        }
        .font(.system(.caption, design: .serif))
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
            let result = try await TravelService.shared.fetchTrips(force: force)
            trips = result.trips
            isOffline = result.isOffline
            loadErrorMessage = nil
        } catch is CancellationError {
            return
        } catch let urlErr as URLError where urlErr.code == .cancelled {
            return
        } catch {
            if trips.isEmpty, let cached = TravelService.shared.tripsDiskCache() {
                trips = cached
                isOffline = true
            }
            // No cache to fall back on: say what failed instead of rendering
            // an empty grid indistinguishable from "no trips yet".
            if trips.isEmpty { loadErrorMessage = error.localizedDescription }
        }
        isLoading = false
    }

    private func loadErrorState(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(.title2, design: .serif))
                .foregroundStyle(Color.sunAccent)
            Text("Couldn't load trips")
                .font(.system(.headline, design: .serif))
                .foregroundStyle(Color.sunText)
            Text(message)
                .font(.system(.caption, design: .serif))
                .foregroundStyle(Color.sunSecondary)
                .multilineTextAlignment(.center)
            Button("Retry") {
                Task { await loadTrips(force: true) }
            }
            .font(.system(.subheadline, design: .serif))
            .foregroundStyle(Color.sunAccent)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // FNV-1a, NOT String.hashValue: hashValue is randomized per launch, which
    // made cover-less trip cards change gradient on every cold start.
    private func stableGradientIndex(_ id: String) -> Int {
        var h: UInt64 = 0xcbf29ce484222325
        for b in id.utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
        return Int(h % UInt64(gradients.count))
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
                        .font(.system(.caption2, design: .serif, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color(hex: status.colorHex))
                        .clipShape(Capsule())
                }

                // Trip name
                Text(trip.name)
                    .font(.system(.title3, design: .serif, weight: .bold))
                    .fontDesign(.serif)
                    .foregroundStyle(.white)
                    .lineLimit(2)

                // Location + dates
                HStack(spacing: 8) {
                    if !trip.location.isEmpty {
                        Text(trip.location)
                            .font(.system(.caption, design: .serif))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    if !trip.dateRangeDisplay.isEmpty {
                        Text(trip.dateRangeDisplay)
                            .font(.system(.caption, design: .serif))
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
