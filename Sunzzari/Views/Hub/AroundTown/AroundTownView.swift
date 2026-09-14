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
                AroundTownMapView(items: $items, initialKind: initialKind)
            }
        }
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        let r0 = NotionService.shared.restaurantsDiskCache() ?? []
        let a0 = NotionService.shared.activitiesDiskCache() ?? []
        if !r0.isEmpty || !a0.isEmpty {
            items = build(r0, a0)
        }
        do {
            async let r = NotionService.shared.fetchRestaurants()
            async let a = NotionService.shared.fetchActivities()
            items = try await build(r, a)
        } catch { /* keep disk data */ }
    }

    private func build(_ restaurants: [Restaurant], _ activities: [Activity]) -> [AroundTownItem] {
        restaurants.compactMap { AroundTownItem.from($0) }
        + activities.compactMap { AroundTownItem.from($0) }
    }
}
