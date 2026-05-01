import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0
    @State private var showIdentitySetup = false
    @State private var showWeeklyBestOf = false
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
        .sheet(isPresented: $showWeeklyBestOf) {
            WeeklyBestOfInputView()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openWeeklyBestOf)) { _ in
            showWeeklyBestOf = true
        }
        .task {
            if AppIdentity.current == nil {
                showIdentitySetup = true
            }
            // Drain cold-launch deep-link buffer — handles the race where didReceive
            // posted before onReceive was attached (notification tapped from killed state).
            if AppDelegate.pendingWeeklyBestOfDeepLink {
                AppDelegate.pendingWeeklyBestOfDeepLink = false
                showWeeklyBestOf = true
            }
            await BoopService.shared.checkForBoops()
            await StatusService.shared.checkForStatus()
            await LocationService.shared.requestAlwaysAuthorization()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task {
                    // Sync badge to notifications still in iOS Notification Center.
                    // Replaces the previous setBadgeCount(0) which wiped the count
                    // every time the app opened, so users never saw it accumulate.
                    let delivered = await UNUserNotificationCenter.current().deliveredNotifications()
                    UNUserNotificationCenter.current().setBadgeCount(delivered.count)
                    await BoopService.shared.checkForBoops()
                    await StatusService.shared.checkForStatus()
                    await DailySetupService.shared.runDailySetup()
                }
            }
        }
    }
}
