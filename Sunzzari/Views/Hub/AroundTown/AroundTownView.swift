import SwiftUI

struct AroundTownView: View {
    /// Opens the map pre-filtered. My Restaurants' map button arrives here on
    /// `.restaurant`: this is the one LA / SF Bay map now, so a caller that only
    /// cares about restaurants says so instead of getting its own map.
    var initialKind: AroundTownItem.Kind? = nil

    @State private var items: [AroundTownItem] = []
    @State private var isLoading = false

    var body: some View {
        ZStack {
            Color.sunBackground.ignoresSafeArea()
            if items.isEmpty && isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                        .tint(Color.sunAccent)
                    Text("Loading Around Town...")
                        .font(.system(.subheadline, design: .serif))
                        .foregroundStyle(Color.sunSecondary)
                }
            } else {
                AroundTownMapView(items: $items, initialKind: initialKind, onLocationSaved: { await load() })
            }
        }
        .task { await load() }
    }

    /// The server's answer, with the last one from disk shown first and kept
    /// when the server cannot be reached (offline, on a plane).
    private func load() async {
        isLoading = true
        defer { isLoading = false }
        if items.isEmpty, let cached = AroundTownService.shared.cachedPlaces() {
            items = cached
        }
        if let fresh = try? await AroundTownService.shared.fetchPlaces() {
            items = fresh
        }
    }
}
