import SwiftUI

struct StoriesView: View {
    @State private var stories: [StoryPost] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showCompose = false
    @State private var playingPerson: StoryPost.Person? = nil
    @State private var showArchive = false
    @State private var yearRecapStories: [StoryPost] = []
    @State private var yearRecapYear: Int = 0
    @State private var showYearRecap = false
    @Environment(\.scenePhase) private var scenePhase

    private static let yearRecapShownKey = "sunzzari_year_recap_shown"

    private static let dayHeader: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d"
        return f
    }()

    private var currentPerson: StoryPost.Person {
        AppIdentity.isHummingbird ? .cathy : .elisa
    }

    /// Carousel order matches Instagram/Snapchat: current user first (the
    /// "post your own" affordance), then others sorted by their most recent
    /// post desc, then anyone with no active stories.
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
        let inactiveOthers = others.filter { latestByPerson[$0] == nil }
        return [me] + activeOthers + inactiveOthers
    }

    /// Reels for one person, newest first per user spec: a fresh post plays
    /// first, then older ones from the past 24h.
    private func reel(for person: StoryPost.Person) -> [StoryPost] {
        stories.filter { $0.person == person }
            .sorted { $0.postedAt > $1.postedAt }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                Color.sunBackground.ignoresSafeArea()

                VStack(spacing: 0) {
                    SerifNavHeader("Stories", showsBack: false)

                    if isLoading && stories.isEmpty {
                        Spacer()
                        ProgressView().tint(.sunAccent)
                        Spacer()
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 24) {
                                Text(Self.dayHeader.string(from: Date()))
                                    .font(.system(.subheadline, design: .serif))
                                    .foregroundStyle(Color.sunSecondary)
                                    .padding(.horizontal, 20)

                                personCarousel
                                    .padding(.horizontal, 4)

                                if stories.isEmpty {
                                    emptyState
                                } else {
                                    Button {
                                        showArchive = true
                                    } label: {
                                        HStack {
                                            Image(systemName: "rectangle.stack")
                                            Text("Archive")
                                        }
                                        .font(.system(.subheadline, design: .serif, weight: .semibold))
                                        .foregroundStyle(Color.sunAccent)
                                    }
                                    .padding(.horizontal, 20)
                                }
                            }
                            .padding(.top, 16)
                            .padding(.bottom, 100)
                        }
                        .refreshable { await load(force: true) }
                    }
                }

                composeFAB
                    .padding(.trailing, 20)
                    .padding(.bottom, 24)
            }
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
            // indexed the just-posted record yet, making the new story flicker
            // out for several seconds before reappearing on the next refresh.
            // The next natural refresh (scenePhase active or pull-to-refresh)
            // will reconcile.
            StoryComposeView { newPost in
                stories.insert(newPost, at: 0)
            }
        }
        .fullScreenCover(item: Binding(
            get: { playingPerson.map { PersonPlayback(person: $0) } },
            set: { playingPerson = $0?.person }
        )) { playback in
            // Build the active person ordering once, when the cover opens. The
            // tray then owns its own `currentPerson` state so swipe and auto-
            // advance happen inside the cover, with no dismiss/re-present.
            let activePersons = rankedPersons.filter { !reel(for: $0).isEmpty }
            StoryTrayView(
                persons: activePersons,
                startingPerson: playback.person,
                reelFor: { reel(for: $0) },
                onDismiss: { playingPerson = nil }
            )
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
            // Refresh on every foreground so a story posted while the app was
            // backgrounded shows up without requiring a manual pull-to-refresh.
            if phase == .active {
                Task { await load(force: true) }
            }
        }
    }

    /// At the end of one person's reel, hop to the next person who has active
    /// stories (Instagram tray behavior). Defensive against background refresh
    /// races: if `person` evaporated from the active list mid-playback, fall
    /// through to the first active person rather than dismissing immediately.
    private func advanceToNextPerson(after person: StoryPost.Person) {
        let withActive = rankedPersons.filter { !reel(for: $0).isEmpty }
        if let idx = withActive.firstIndex(of: person), idx + 1 < withActive.count {
            playingPerson = withActive[idx + 1]
        } else if withActive.firstIndex(of: person) == nil, let first = withActive.first {
            playingPerson = first
        } else {
            playingPerson = nil
        }
    }

    /// Auto-present the year recap once on Dec 31 each year. Tracks last-shown
    /// year in UserDefaults so the recap doesn't re-appear on every foreground.
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

    // MARK: - Sections

    private var personCarousel: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(rankedPersons, id: \.self) { person in
                    personCircle(for: person)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func personCircle(for person: StoryPost.Person) -> some View {
        let theirs = reel(for: person)
        let hasActive = !theirs.isEmpty
        let preview = theirs.first?.thumbnailURL
        let isMe = person == currentPerson

        return Button {
            if hasActive {
                playingPerson = person
            } else if isMe {
                // Own ring with no active stories: tap opens compose, matching
                // Instagram where your own avatar is always actionable as
                // "post a story."
                showCompose = true
            }
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .stroke(
                            hasActive ? Color(hex: person.colorHex) : Color.sunSecondary.opacity(0.4),
                            lineWidth: hasActive ? 3 : 1.5
                        )
                        .frame(width: 78, height: 78)

                    Group {
                        if hasActive, let preview {
                            AsyncImage(url: preview) { phase in
                                switch phase {
                                case .success(let image):
                                    image.resizable().scaledToFill()
                                default:
                                    Color(hex: person.colorHex).opacity(0.3)
                                }
                            }
                        } else {
                            Color(hex: person.colorHex).opacity(0.2)
                                .overlay(
                                    Text(String(person.rawValue.prefix(1)))
                                        .font(.system(size: 24, weight: .semibold, design: .serif))
                                        .foregroundStyle(Color(hex: person.colorHex))
                                )
                        }
                    }
                    .frame(width: 68, height: 68)
                    .clipShape(Circle())

                    // IG-style "post your own" plus badge: only on the user's
                    // own ring, indicating tap-to-compose is always available.
                    if isMe {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(Color.sunAccent, Color.sunBackground)
                            .offset(x: 26, y: 26)
                    }
                }
                Text(person.rawValue)
                    .font(.system(.caption, design: .serif, weight: hasActive ? .semibold : .regular))
                    .foregroundStyle(hasActive ? Color.sunText : Color.sunSecondary)
            }
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "camera.fill")
                .font(.system(size: 44, design: .serif))
                .foregroundStyle(Color.sunAccent)
            Text("No stories today")
                .font(.system(.headline, design: .serif))
                .foregroundStyle(Color.sunText)
            Text("Tap the + to share a moment")
                .font(.system(.subheadline, design: .serif))
                .foregroundStyle(Color.sunSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

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

    /// Warm URLCache for every active story so tapping any ring opens to a
    /// fully-loaded image and tap-next never waits on the network. Skipped on
    /// cellular, Low Data Mode, and constrained paths so we don't drain a
    /// tester's data plan; AsyncImage fetches on-demand in that case.
    private func prefetchAllActiveStories() {
        guard NetworkMonitor.shared.isUnconstrained else { return }
        let urls: [URL] = stories.compactMap { $0.fullURL }
        for url in urls {
            Task.detached { _ = try? await URLSession.shared.data(from: url) }
        }
    }
}

private struct PersonPlayback: Identifiable {
    let person: StoryPost.Person
    var id: String { person.rawValue }
}
