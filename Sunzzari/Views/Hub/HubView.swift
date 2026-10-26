import SwiftUI

struct HubView: View {

    /// Set by ContentView at launch to reopen the trip Elisa was last on.
    /// Bound rather than local so clearing it (she taps Back) sticks.
    @Binding var resumeTrip: Trip?

    init(resumeTrip: Binding<Trip?> = .constant(nil)) {
        _resumeTrip = resumeTrip
    }

    // Four fixed cards laid out NON-lazily. Around Town is here AND on the home
    // page above the Boops. Elisa, 2026-10-25: "make sure to add around town to
    // hub ... also you can eliminate restaurants and actiities because those are
    // encapsulated on around town". The Restaurants and Activities screens are
    // still opened from the home page lists.
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
         .init(title: "Elisa's Map", subtitle: "Every place, LA first",   symbolName: "mappin.and.ellipse")]
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
                                    // A lone card keeps its half-width size.
                                    if rows[row].count == 1 {
                                        Color.clear.frame(maxWidth: .infinity).frame(height: 1)
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
            .navigationDestination(item: $resumeTrip) { trip in
                TripTodayView(trip: trip)
            }
        }
    }

    @ViewBuilder
    private func destination(for title: String) -> some View {
        switch title {
        case "Travel":      TravelView()
        case "Gallery":     GalleryView()
        case "Wine":        WineHubView()
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
