import SwiftUI

struct HubView: View {
    @State private var restaurantsCover: String? = nil
    @State private var wineCover: String? = nil
    @State private var activitiesCover: String? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                Color.sunBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        NavigationLink(destination: RestaurantHubView()) {
                            HubCardView(title: "Restaurants", subtitle: "My Guide", coverURL: restaurantsCover)
                        }
                        .buttonStyle(.plain)

                        NavigationLink(destination: WineHubView()) {
                            HubCardView(title: "Wine", subtitle: "My Collection", coverURL: wineCover)
                        }
                        .buttonStyle(.plain)

                        NavigationLink(destination: ActivitiesHubView()) {
                            HubCardView(title: "Activities", subtitle: "Things To Do", coverURL: activitiesCover)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)
                }
            }
            .navigationTitle("Hub")
            .navigationBarTitleDisplayMode(.large)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .task { await fetchCovers() }
        }
    }

    private func fetchCovers() async {
        // Restaurant Guide is inline="true" — cover lives on its parent page
        // Wine and Activities are full-page databases — cover is on the DB page itself
        // Restaurants and Wine are inline databases — covers live on their parent pages
        // Activities is a non-inline database — cover lives on the database page itself
        async let r = try? NotionService.shared.fetchDatabaseCover(id: "2eef3cdd-67a4-81d9-b0b8-ee01948cd7c9")
        async let w = try? NotionService.shared.fetchDatabaseCover(id: "2eef3cdd-67a4-8190-a326-f42cf3d2d075")
        async let a = try? NotionService.shared.fetchDatabaseCover(id: "322f3cdd-67a4-80bd-966d-cbf0affa14d9")
        let (rc, wc, ac) = await (r, w, a)
        restaurantsCover = rc
        wineCover = wc
        activitiesCover = ac
    }
}
