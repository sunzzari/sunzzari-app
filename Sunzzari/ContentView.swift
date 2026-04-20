import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0
    @State private var showIdentitySetup = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                TodayView()
                    .tabItem {
                        Label("Home", systemImage: "sparkles")
                    }
                    .tag(0)

                ThoughtActionView()
                    .tabItem {
                        Label("Thoughts", systemImage: "lightbulb.fill")
                    }
                    .tag(1)

                StatusView()
                    .tabItem {
                        Label("Status", systemImage: "bolt.horizontal.circle.fill")
                    }
                    .tag(2)

                HubView()
                    .tabItem {
                        Label("Hub", systemImage: "square.grid.2x2.fill")
                    }
                    .tag(3)

                UtilityView()
                    .tabItem {
                        Label("More", systemImage: "ellipsis.circle.fill")
                    }
                    .tag(4)
            }
            .tint(.sunAccent)
            .fontDesign(.serif)

            // Warm ambient glow — two-point radial system matching travel map body::before
            GeometryReader { geo in
                ZStack {
                    RadialGradient(
                        colors: [Color(hex: "#FBBF24").opacity(0.10), .clear],
                        center: .init(x: 0.0, y: 1.0),
                        startRadius: 0,
                        endRadius: geo.size.height * 0.55
                    )
                    RadialGradient(
                        colors: [Color(hex: "#F97316").opacity(0.05), .clear],
                        center: .init(x: 1.0, y: 0.0),
                        startRadius: 0,
                        endRadius: geo.size.width * 0.6
                    )
                }
                .ignoresSafeArea()
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
        .sheet(isPresented: $showIdentitySetup) {
            SettingsView(onComplete: { showIdentitySetup = false })
                .interactiveDismissDisabled(true)
        }
        .task {
            if AppIdentity.current == nil {
                showIdentitySetup = true
            }
            await BoopService.shared.checkForBoops()
            await StatusService.shared.checkForStatus()
            await LocationService.shared.requestAlwaysAuthorization()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                UNUserNotificationCenter.current().setBadgeCount(0)
                Task {
                    await BoopService.shared.checkForBoops()
                    await StatusService.shared.checkForStatus()
                    await DailySetupService.shared.runDailySetup()
                }
            }
        }
    }
}
