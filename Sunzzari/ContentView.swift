import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            TodayView()
                .tabItem {
                    Label("Today", systemImage: "sparkles")
                }
                .tag(0)

            GalleryView()
                .tabItem {
                    Label("Gallery", systemImage: "photo.on.rectangle.angled")
                }
                .tag(1)

            BestOfView()
                .tabItem {
                    Label("Best Of", systemImage: "star.circle.fill")
                }
                .tag(2)

            TravelView()
                .tabItem {
                    Label("Travel", systemImage: "airplane.circle.fill")
                }
                .tag(3)

            SearchView()
                .tabItem {
                    Label("Search", systemImage: "magnifyingglass")
                }
                .tag(4)

            NitsAndBugsView()
                .tabItem {
                    Label("Nits & Bugs", systemImage: "ladybug")
                }
                .tag(5)
        }
        .tint(.sunAccent)
        .onAppear {
            let appearance = UITabBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = UIColor(Color.sunBackground)
            UITabBar.appearance().standardAppearance = appearance
            UITabBar.appearance().scrollEdgeAppearance = appearance
        }
    }
}
