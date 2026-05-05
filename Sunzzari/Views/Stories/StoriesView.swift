import SwiftUI

/// Full-bleed Stories tab. Opens directly into the auto-playing player when
/// active stories exist, mirroring Snapchat / Instagram-tab UX. The carousel
/// of person rings was deliberately removed -- on a 2-person couple app, a
/// rings UI is friction; the player IS the home view here.
///
/// Chrome (archive button + compose FAB) floats over the player as glass-blur
/// overlays. The X button inside the player switches back to the Today tab
/// rather than dismissing-to-nothing, since the tab itself is the player.
///
/// Empty state (no active stories) is a black background with a centered
/// compose CTA so the visual feel of opening the tab is consistent --
/// always full-bleed, never a "list" surface.
struct StoriesView: View {
    @Binding var selectedTab: Int

    @State private var stories: [StoryPost] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showCompose = false
    @State private var showArchive = false
    @State private var yearRecapStories: [StoryPost] = []
    @State private var yearRecapYear: Int = 0
    @State private var showYearRecap = false
    @Environment(\.scenePhase) private var scenePhase

    private static let yearRecapShownKey = "sunzzari_year_recap_shown"

    private var currentPerson: StoryPost.Person {
        AppIdentity.isHummingbird ? .cathy : .elisa
    }

    /// Carousel ordering kept (used to pick which reel auto-plays first):
    /// current user first, then others sorted by most-recent post desc.
    private var rankedPersons: [StoryPost.Person] {
        let latestByPerson: [StoryPost.Person: Date] = stories.reduce(into: [:]) { acc, post in
            if let prev = acc[post.person], prev > post.postedAt { return }
            acc[post.person] = post.postedAt
        }
        let me = currentPerson
        let others = StoryPost.Person.allCases.filter { $0 != me }
        let activeOthers = others
            .filter { latestByPerson[$0] != nil }
            .sorted { (latestByPerson[$0] ?? .distantPast) > (latestByPerson[$1] ?? .distantPast) }
        return [me] + activeOthers
    }

    private var activePersons: [StoryPost.Person] {
        rankedPersons.filter { !reel(for: $0).isEmpty }
    }

    /// Reels for one person, newest first per user spec.
    private func reel(for person: StoryPost.Person) -> [StoryPost] {
        stories.filter { $0.person == person }
            .sorted { $0.postedAt > $1.postedAt }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if isLoading && stories.isEmpty {
                    ProgressView().tint(.white)
                } else if activePersons.isEmpty {
                    emptyState
                } else if let starting = activePersons.first {
                    StoryTrayView(
                        persons: activePersons,
                        startingPerson: starting,
                        reelFor: { reel(for: $0) },
                        // X button / drag-down: exit the Stories tab back to
                        // the Today tab. Snapchat / Instagram parity -- there
                        // is no "list" to return to since the tab IS the player.
                        onDismiss: { selectedTab = 0 }
                    )
                    .overlay(alignment: .topLeading) { archiveButton }
                    .overlay(alignment: .bottomTrailing) { composeFAB }
                }
            }
            .ignoresSafeArea()
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showArchive) {
                StoryArchiveView()
            }
            .fullScreenCover(isPresented: $showYearRecap) {
                NavigationStack {
                    YearRecapView(year: yearRecapYear, stories: yearRecapStories)
                }
            }
        }
        .sheet(isPresented: $showCompose) {
            // Don't refetch on dismiss when the optimistic insert already added
            // the new post. Notion's index has 2-15s of lag; an immediate force
            // reload would overwrite `stories` with a server result that hasn't
            // indexed the just-posted record yet.
            StoryComposeView { newPost in
                stories.insert(newPost, at: 0)
            }
        }
        .alert("Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .task {
            await load()
            await maybePresentYearRecap()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await load(force: true) }
            }
        }
    }

    // MARK: - Empty state

    /// Shown when no one has an active story today. Sleek black bleed +
    /// centered call-to-action so the tab still feels like a "place" rather
    /// than a void. Archive + compose are reachable from here too.
    private var emptyState: some View {
        ZStack {
            VStack(spacing: 18) {
                Image(systemName: "sparkles")
                    .font(.system(size: 56, design: .serif))
                    .foregroundStyle(Color.sunAccent)

                Text("No stories today")
                    .font(.system(.title2, design: .serif, weight: .semibold))
                    .foregroundStyle(.white)

                Text("Be the first to share a moment.")
                    .font(.system(.subheadline, design: .serif))
                    .foregroundStyle(.white.opacity(0.7))

                Button {
                    showCompose = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                        Text("Add your story")
                    }
                    .font(.system(.headline, design: .serif, weight: .semibold))
                    .foregroundStyle(Color.sunBackground)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 14)
                    .background(Color.sunAccent)
                    .clipShape(Capsule())
                    .shadow(color: Color.sunAccent.opacity(0.45), radius: 14)
                }
                .padding(.top, 12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topLeading) { archiveButton }
    }

    // MARK: - Floating chrome

    /// Archive entry, top-leading. Glass-blur capsule so it reads against
    /// any photo in the player below. Padded down past the safe-area top so
    /// it doesn't overlap the player's progress bars.
    private var archiveButton: some View {
        Button {
            showArchive = true
        } label: {
            Image(systemName: "rectangle.stack")
                .font(.system(size: 16, weight: .semibold, design: .serif))
                .foregroundStyle(.white)
                .padding(10)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 0.5))
        }
        .padding(.leading, 14)
        .padding(.top, 60)
    }

    /// Compose FAB, bottom-trailing. Lifted above the tab bar (tab bar height
    /// is ~83pt with the home indicator); padding 110 keeps the FAB clear.
    private var composeFAB: some View {
        Button {
            showCompose = true
        } label: {
            Image(systemName: "plus")
                .font(.system(.title2, design: .serif, weight: .bold))
                .foregroundStyle(Color.sunBackground)
                .padding(18)
                .background(Color.sunAccent)
                .clipShape(Circle())
                .shadow(color: Color.sunAccent.opacity(0.5), radius: 12)
        }
        .padding(.trailing, 20)
        .padding(.bottom, 110)
    }

    // MARK: - Year recap

    /// Auto-present the year recap once on Dec 31 each year.
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
        }
    }

    // MARK: - Data

    private func load(force: Bool = false) async {
        if stories.isEmpty, let cached = NotionService.shared.storiesActiveDiskCache() {
            stories = cached
            isLoading = false
            prefetchAllActiveStories()
        }
        do {
            stories = try await NotionService.shared.fetchActiveStories(force: force)
            prefetchAllActiveStories()
        } catch is CancellationError {
        } catch let err as URLError where err.code == .cancelled {
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    /// Warm URLCache so the player opens to a fully-loaded image. Skipped on
    /// cellular / Low Data Mode -- AsyncImage falls back to fetch-on-demand.
    private func prefetchAllActiveStories() {
        guard NetworkMonitor.shared.isUnconstrained else { return }
        let urls: [URL] = stories.compactMap { $0.fullURL }
        for url in urls {
            Task.detached { _ = try? await URLSession.shared.data(from: url) }
        }
    }
}
