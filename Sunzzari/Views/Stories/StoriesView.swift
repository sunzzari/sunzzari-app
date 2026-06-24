import SwiftUI

/// Stories tab is now a pure compose launcher: tapping the tab opens the
/// compose flow immediately, regardless of whether there are stories to view.
/// Viewing stories happens via `StoryHeaderButton` on the Today screen
/// (Instagram-style ring) — which falls back to the archive when nothing is
/// live — and the archive also lives under the More tab.
struct StoriesView: View {
    @Binding var selectedTab: Int

    @State private var showCompose = false
    @State private var stories: [StoryPost] = []
    @State private var yearRecapStories: [StoryPost] = []
    @State private var yearRecapYear: Int = 0
    @State private var showYearRecap = false

    private static let yearRecapShownKey = "sunzzari_year_recap_shown"

    var body: some View {
        ZStack {
            Color.sunBackground.ignoresSafeArea()
        }
        // Present compose whenever the user is on this tab. .onAppear fires
        // every time the tab gains focus, including a re-tap after dismiss.
        .onAppear {
            showCompose = true
        }
        .sheet(isPresented: $showCompose, onDismiss: {
            // Return to Today after compose closes so re-tapping Stories opens
            // a fresh compose instead of sitting on an empty placeholder.
            selectedTab = 0
        }) {
            StoryComposeView { newPost in
                stories.insert(newPost, at: 0)
            }
        }
        .fullScreenCover(isPresented: $showYearRecap) {
            NavigationStack {
                YearRecapView(year: yearRecapYear, stories: yearRecapStories)
            }
        }
        .task { await maybePresentYearRecap() }
    }

    /// Auto-present the year recap once on Dec 31 each year. Survives the tab
    /// rewrite because the .task still fires when the user lands here.
    private func maybePresentYearRecap() async {
        let cal = Calendar.current
        let now = Date()
        let comps = cal.dateComponents([.year, .month, .day], from: now)
        guard comps.month == 12, comps.day == 31, let year = comps.year else { return }
        let lastShown = UserDefaults.standard.integer(forKey: Self.yearRecapShownKey)
        guard lastShown != year else { return }
        do {
            let yearStories = try await NotionService.shared.fetchArchiveStories(year: year)
            guard !yearStories.isEmpty else { return }
            yearRecapStories = yearStories
            yearRecapYear = year
            showYearRecap = true
            UserDefaults.standard.set(year, forKey: Self.yearRecapShownKey)
        } catch {
            #if DEBUG
            print("[YearRecap] fetch failed:", error.localizedDescription)
            #endif
        }
    }
}

/// Instagram-style story ring shown in the Today page header. This is the
/// permanent entry point for viewing stories — it always renders.
///
/// When the partner has an active story (24h window) it shows their initial
/// inside a colored ring: solid accent if any story is unseen, faded grey once
/// everything has been viewed. Tapping opens the live reel.
///
/// When there are no active partner stories it falls back to a faded dashed
/// "stories" ring that opens the archive, so there's always a way in.
struct StoryHeaderButton: View {
    @State private var stories: [StoryPost] = []
    @State private var showPlayer = false
    @State private var showArchive = false
    @Environment(\.scenePhase) private var scenePhase

    private var currentPerson: StoryPost.Person {
        AppIdentity.isHummingbird ? .cathy : .elisa
    }

    private var partnerStories: [StoryPost] {
        stories.filter { $0.person != currentPerson }
            .sorted { $0.postedAt > $1.postedAt }
    }

    private var partnersWithStories: [StoryPost.Person] {
        let latestByPerson: [StoryPost.Person: Date] = partnerStories.reduce(into: [:]) { acc, post in
            if let prev = acc[post.person], prev > post.postedAt { return }
            acc[post.person] = post.postedAt
        }
        return latestByPerson
            .sorted { $0.value > $1.value }
            .map(\.key)
    }

    private var hasUnseen: Bool {
        SeenStoriesStore.shared.unseenCount(in: partnerStories) > 0
    }

    var body: some View {
        Group {
            if let partner = partnersWithStories.first {
                Button {
                    showPlayer = true
                } label: {
                    ZStack {
                        Circle()
                            .stroke(
                                hasUnseen ? Color.sunAccent : Color.white.opacity(0.25),
                                lineWidth: 2
                            )
                            .frame(width: 34, height: 34)

                        Circle()
                            .fill(Color(hex: partner.colorHex))
                            .frame(width: 26, height: 26)
                            .overlay(
                                Text(String(partner.rawValue.prefix(1)))
                                    .font(.system(size: 12, weight: .bold, design: .serif))
                                    .foregroundStyle(.white)
                            )
                    }
                }
                .accessibilityLabel("View \(partner.rawValue)'s story")
            } else {
                // No live story — permanent fallback ring into the archive.
                Button {
                    showArchive = true
                } label: {
                    ZStack {
                        Circle()
                            .strokeBorder(
                                Color.white.opacity(0.25),
                                style: StrokeStyle(lineWidth: 2, dash: [3, 3])
                            )
                            .frame(width: 34, height: 34)

                        Image(systemName: "circle.dashed.inset.filled")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.45))
                    }
                }
                .accessibilityLabel("View story archive")
            }
        }
        .fullScreenCover(isPresented: $showPlayer) {
            StoryTrayView(
                persons: partnersWithStories,
                startingPerson: partnersWithStories.first ?? currentPerson,
                reelFor: { person in
                    partnerStories.filter { $0.person == person }
                },
                onDismiss: { showPlayer = false }
            )
            .ignoresSafeArea()
            .statusBarHidden(true)
        }
        .sheet(isPresented: $showArchive) {
            NavigationStack {
                StoryArchiveView()
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Done") { showArchive = false }
                                .foregroundStyle(Color.sunAccent)
                        }
                    }
            }
        }
        .task { await load() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await load(force: true) } }
        }
        .onReceive(NotificationCenter.default.publisher(for: .storiesDidMarkSeen)) { _ in
            // Re-eval ring colour without a Notion roundtrip.
            stories = stories
        }
    }

    private func load(force: Bool = false) async {
        if stories.isEmpty, let cached = NotionService.shared.storiesActiveDiskCache() {
            stories = cached
        }
        do {
            stories = try await NotionService.shared.fetchActiveStories(force: force)
        } catch {
            // Silent failure — header element should never block the screen.
        }
    }
}
