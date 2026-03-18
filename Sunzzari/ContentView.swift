import SwiftUI
import UIKit

struct ContentView: View {
    @State private var selectedTab = 0
    @State private var showBoopSheet = false
    @State private var showStatusSheet = false
    @State private var showThoughtActionSheet = false
    @State private var showIdentitySetup = false
    @State private var hideFloatingButtons = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
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

                HubView()
                    .tabItem {
                        Label("Hub", systemImage: "square.grid.2x2.fill")
                    }
                    .tag(2)

                TravelView()
                    .tabItem {
                        Label("Travel", systemImage: "airplane.circle.fill")
                    }
                    .tag(3)

                BestOfView()
                    .tabItem {
                        Label("Best Of", systemImage: "star.circle.fill")
                    }
                    .tag(4)

                SearchView()
                    .tabItem {
                        Label("Search", systemImage: "magnifyingglass")
                    }
                    .tag(5)

                CycleView()
                    .tabItem {
                        Label("Cycle", systemImage: "calendar.circle.fill")
                    }
                    .tag(6)

                CardsView()
                    .tabItem {
                        Label("Cards", systemImage: "creditcard.circle.fill")
                    }
                    .tag(7)

                InfoView()
                    .tabItem {
                        Label("Reference", systemImage: "bookmark.circle.fill")
                    }
                    .tag(8)

                SettingsView(onComplete: {})
                    .tabItem {
                        Label("Settings", systemImage: "gearshape.fill")
                    }
                    .tag(9)

                NitsAndBugsView()
                    .tabItem {
                        Label("Nits & Bugs", systemImage: "ladybug")
                    }
                    .tag(10)
            }
            .tint(.sunAccent)
            .onAppear {
                // Appearance is configured globally in AppDelegate.didFinishLaunchingWithOptions
                // so that .toolbarBackground() modifiers in views cannot override the serif font.
            }

            // Warm ambient glow — two-point radial system matching travel map body::before
            GeometryReader { geo in
                ZStack {
                    // Bottom-left warm glow (primary)
                    RadialGradient(
                        colors: [Color(hex: "#FBBF24").opacity(0.10), .clear],
                        center: .init(x: 0.0, y: 1.0),
                        startRadius: 0,
                        endRadius: geo.size.height * 0.55
                    )
                    // Top-right secondary glow
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

            // Floating buttons — hidden on More page and overflow tabs so they don't block content
            if !hideFloatingButtons {
            VStack {
                HStack {
                    Spacer()
                    HStack(spacing: 8) {
                        Button {
                            showThoughtActionSheet = true
                        } label: {
                            Text("thought-action")
                                .font(.callout)
                                .fontWeight(.bold)
                                .foregroundStyle(Color.sunBackground)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Color(hex: "#C084FC"))
                                .clipShape(Capsule())
                                .shadow(color: Color(hex: "#C084FC").opacity(0.5), radius: 10, x: 0, y: 3)
                        }

                        Button {
                            showStatusSheet = true
                        } label: {
                            Text("status")
                                .font(.callout)
                                .fontWeight(.bold)
                                .foregroundStyle(Color.sunBackground)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Color(hex: "#38BDF8"))
                                .clipShape(Capsule())
                                .shadow(color: Color(hex: "#38BDF8").opacity(0.5), radius: 10, x: 0, y: 3)
                        }

                        Button {
                            showBoopSheet = true
                        } label: {
                            Text("boop")
                                .font(.callout)
                                .fontWeight(.bold)
                                .foregroundStyle(Color.sunBackground)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color.sunAccent)
                                .clipShape(Capsule())
                                .shadow(color: Color.sunAccent.opacity(0.5), radius: 10, x: 0, y: 3)
                        }
                    }
                    .padding(.trailing, 16)
                }
                Spacer()
            }
            .padding(.top) // respects safe area (below Dynamic Island / status bar)
            } // end if !hideFloatingButtons
        }
        .sheet(isPresented: $showThoughtActionSheet) {
            ThoughtActionView()
        }
        .sheet(isPresented: $showBoopSheet) {
            BoopView()
        }
        .sheet(isPresented: $showStatusSheet) {
            StatusView()
        }
        .sheet(isPresented: $showIdentitySetup) {
            SettingsView(onComplete: { showIdentitySetup = false })
                .interactiveDismissDisabled(true)
        }
        // Hide floating buttons on the More page or any overflow tab (tag ≥ 4)
        .onReceive(Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()) { _ in
            let onOverflow = selectedTab >= 4
            let onMoreList = Self.isMoreNavigationActive()
            let shouldHide = onOverflow || onMoreList
            if shouldHide != hideFloatingButtons { hideFloatingButtons = shouldHide }
        }
        .task {
            // Show identity picker on first launch
            if AppIdentity.current == nil {
                showIdentitySetup = true
            }
            // Check for boops and status on initial launch
            await BoopService.shared.checkForBoops()
            await StatusService.shared.checkForStatus()
            await LocationService.shared.requestAlwaysAuthorization()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task {
                    await BoopService.shared.checkForBoops()
                    await StatusService.shared.checkForStatus()
                    // First foreground of a new day: run daily setup (picks today's entry,
                    // schedules 9am notification). Idempotent — skips if already done today.
                    await DailySetupService.shared.runDailySetup()
                }
            }
        }
    }

    // MARK: - Helpers

    /// Returns true when iOS is showing the More navigation list (not a tab within it).
    private static func isMoreNavigationActive() -> Bool {
        guard
            let scene = UIApplication.shared.connectedScenes
                .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
            let tabBar = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController as? UITabBarController
        else { return false }
        return tabBar.selectedViewController === tabBar.moreNavigationController
    }
}
