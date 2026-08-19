import SwiftUI

struct HubView: View {

    // Six fixed cards laid out NON-lazily.
    //
    // This was a LazyVGrid. With only six always-visible cards there is nothing to
    // gain from laziness, and lazy containers are where NavigationLink(destination:)
    // misbinds: the container creates and recycles cells on its own schedule, and a
    // card can end up wired to a neighbour's destination. Elisa hit exactly that on
    // device -- tapping Wine (index 2) opened Activities (index 4), one row down in
    // the same column, deterministically. It never reproduced in the simulator, so
    // the laziness is removed rather than worked around.
    private let rows: [[HubCard]] = [
        [.init(title: "Travel",      subtitle: "Our Trips",     symbolName: "map.fill"),
         .init(title: "Gallery",     subtitle: "Our Memories",  symbolName: "photo.stack.fill")],
        [.init(title: "Wine",        subtitle: "My Collection", assetName: "hubWine"),
         .init(title: "Restaurants", subtitle: "My Guide",      assetName: "hubRestaurants")],
        [.init(title: "Activities",  subtitle: "Things To Do",  assetName: "hubActivities"),
         .init(title: "Around Town", subtitle: "LA & SF Bay",   symbolName: "mappin.and.ellipse")]
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.sunBackground.ignoresSafeArea()

                VStack(spacing: 0) {
                    PageHeader("Hub")

                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(rows.indices, id: \.self) { row in
                                HStack(spacing: 12) {
                                    ForEach(rows[row]) { card in
                                        NavigationLink {
                                            destination(for: card.title)
                                        } label: {
                                            HubCardView(
                                                title: card.title,
                                                subtitle: card.subtitle,
                                                assetName: card.assetName,
                                                symbolName: card.symbolName
                                            )
                                        }
                                        .buttonStyle(.plain)
                                        .frame(maxWidth: .infinity)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 20)
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    @ViewBuilder
    private func destination(for title: String) -> some View {
        switch title {
        case "Travel":      TravelView()
        case "Gallery":     GalleryView()
        case "Wine":        WineHubView()
        case "Restaurants": RestaurantHubView()
        case "Activities":  ActivitiesHubView()
        default:            AroundTownView()
        }
    }
}

private struct HubCard: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    var assetName: String? = nil
    var symbolName: String? = nil
}

#Preview {
    HubView()
}
