import SwiftUI

/// Full-bleed Snapchat/Instagram-style player for one author's recent stories.
/// Tap the right half to advance, tap the left half to go back, hold anywhere
/// to pause. Author and caption overlay over the photo. Dismiss is via the X
/// button only -- swipe-down was removed because it left a black bar at the
/// top when partial drags didn't cross the dismiss threshold.
struct StoryPlayerView: View {
    let stories: [StoryPost]
    let person: StoryPost.Person
    let onDismiss: () -> Void
    /// Called when the reel ends naturally (last story finished). Distinct from
    /// onDismiss so the parent can auto-advance to the next person's reel
    /// (Instagram tray behavior). If nil, falls back to onDismiss.
    var onReelComplete: (() -> Void)? = nil
    /// Tap-back on the first story asks the parent to swipe to the previous
    /// person. If nil or no previous, behaves as a no-op (IG default).
    var onRequestPrevious: (() -> Void)? = nil
    /// When false, the progress timer halts. Used by the parent TabView to make
    /// non-visible reels stop running their clock and audio.
    var isActive: Bool = true

    @State private var currentIndex: Int = 0
    @State private var progress: Double = 0
    @State private var isPaused: Bool = false
    @State private var prefetchedURLs: Set<URL> = []

    private let storyDuration: TimeInterval = 5.0
    private let tickInterval: TimeInterval = 0.05
    /// Height of the top header content (progress bars + author chip + close
    /// button + their padding). Stacked on top of the device's top safe-area
    /// inset so taps on the X button or progress bars never fall through to
    /// the advance/back tap zones below.
    private let headerTapInset: CGFloat = 60

    private static let postedAtFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    /// Time chip in the player header. Within the last hour: "2m ago" (warm,
    /// IG-parity). Same day after that: "9:42 AM". Yesterday: "Yesterday 11:00
    /// PM" — the explicit day prefix matters when the 24h rolling window
    /// crosses midnight (a story posted at 11pm and viewed at 9am is 10h old,
    /// not 22h).
    private func relativeTimeLabel(for date: Date) -> String {
        let now = Date()
        let elapsed = now.timeIntervalSince(date)
        if elapsed >= 0 && elapsed < 3600 {
            return Self.relativeFormatter.localizedString(for: date, relativeTo: now)
        }
        let cal = Calendar.current
        let timeStr = Self.postedAtFormatter.string(from: date)
        if cal.isDateInToday(date) { return timeStr }
        if cal.isDateInYesterday(date) { return "Yesterday \(timeStr)" }
        return timeStr
    }

    private var currentStory: StoryPost? {
        guard stories.indices.contains(currentIndex) else { return nil }
        return stories[currentIndex]
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                if let currentStory {
                    AsyncImage(url: currentStory.fullURL) { phase in
                        switch phase {
                        case .empty:
                            ProgressView().tint(.white)
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        case .failure:
                            VStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.system(size: 32, design: .serif))
                                Text("Couldn't load photo")
                                    .font(.system(.subheadline, design: .serif))
                            }
                            .foregroundStyle(.white.opacity(0.7))
                        @unknown default:
                            EmptyView()
                        }
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    .ignoresSafeArea()
                }

                // Caption overlay (bottom-leading)
                if let caption = currentStory?.caption, !caption.isEmpty {
                    VStack {
                        Spacer()
                        Text(caption)
                            .font(.system(.body, design: .serif, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Color.black.opacity(0.45))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .padding(.horizontal, 20)
                            .padding(.bottom, 60)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                // Tap zones — pushed below the top header so taps on the
                // progress bars, author name, or close button don't fall
                // through to advance/goBack. Inset = device safe area top +
                // header content height (works on Dynamic Island, notch, SE).
                VStack(spacing: 0) {
                    Color.clear.frame(height: geo.safeAreaInsets.top + headerTapInset)
                    HStack(spacing: 0) {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { goBack() }
                            .accessibilityLabel("Previous story")
                            .accessibilityAddTraits(.isButton)
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { advance() }
                            .accessibilityLabel("Next story")
                            .accessibilityAddTraits(.isButton)
                    }
                }

                // Top: progress bars + author chip + close
                VStack(spacing: 10) {
                    progressBars
                    headerRow
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
            }
            // Tracks finger-down across press AND release. LongPressGesture's
            // onEnded fires when minimumDuration is met (not on lift), which is
            // why a plain .gesture(LongPressGesture()...) does not work for pause.
            .onLongPressGesture(minimumDuration: 0.2, maximumDistance: 50) {
                // perform: required closure, intentionally empty
            } onPressingChanged: { pressing in
                isPaused = pressing
            }
            // Re-keys the progress task on (a) index advance, (b) tab activation
            // change. When the parent TabView swipes to another person this view
            // becomes inactive -- task cancels, timer stops. On swipe back it
            // restarts from the current index.
            .task(id: PlayKey(index: currentIndex, active: isActive)) {
                guard isActive else { return }
                await runProgressLoop()
            }
            .statusBarHidden(true)
        }
    }

    private struct PlayKey: Hashable {
        let index: Int
        let active: Bool
    }

    // MARK: - Top header

    private var progressBars: some View {
        HStack(spacing: 4) {
            ForEach(stories.indices, id: \.self) { i in
                GeometryReader { rowGeo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.25))
                        Capsule()
                            .fill(Color.white)
                            .frame(width: rowGeo.size.width * fillFraction(for: i))
                    }
                }
                .frame(height: 3)
            }
        }
    }

    private var headerRow: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color(hex: person.colorHex))
                .frame(width: 28, height: 28)
                .overlay(
                    Text(String(person.rawValue.prefix(1)))
                        .font(.system(size: 12, weight: .bold, design: .serif))
                        .foregroundStyle(.white)
                )

            VStack(alignment: .leading, spacing: 0) {
                Text(person.rawValue)
                    .font(.system(.subheadline, design: .serif, weight: .semibold))
                    .foregroundStyle(.white)
                if let story = currentStory {
                    HStack(spacing: 4) {
                        Text(relativeTimeLabel(for: story.postedAt))
                        if let location = story.location, !location.isEmpty {
                            Text("•")
                            Text(location)
                        }
                    }
                    .font(.system(.caption, design: .serif))
                    .foregroundStyle(.white.opacity(0.85))
                }
            }

            Spacer()

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold, design: .serif))
                    .foregroundStyle(.white)
                    .padding(8)
                    .background(Color.black.opacity(0.35))
                    .clipShape(Circle())
            }
        }
    }

    private func fillFraction(for i: Int) -> Double {
        if i < currentIndex { return 1.0 }
        if i == currentIndex { return progress }
        return 0
    }

    // MARK: - Playback

    /// Wall-clock-anchored progress loop. Pause works by accumulating paused
    /// time and subtracting it from elapsed-since-start, so a 5s story actually
    /// takes 5s of unpaused time even under system load (no Task.sleep drift).
    /// Prefetches the next story's image at the halfway mark so AsyncImage hits
    /// URLCache instead of round-tripping when the user taps next.
    ///
    /// Resume-on-swipe-back: when TabView swipes to another reel and back, the
    /// .task(id:) cancels and re-fires. We anchor `startDate` so elapsed time
    /// equals the saved `progress`, and the bar continues smoothly from where
    /// it paused instead of snapping back to zero. New stories enter with
    /// progress=0 (set by advance() before the index changes) so this is also
    /// correct for fresh segments.
    ///
    /// `@MainActor` is explicit (not just inherited from the View) because the
    /// loop awaits `Task.sleep` and then mutates `@State progress`. Without it,
    /// strict-concurrency builds would warn about resuming on a non-Main
    /// executor when writing back to state.
    @MainActor
    private func runProgressLoop() async {
        if progress >= 1.0 { progress = 0 }
        let anchor = progress
        let startDate = Date().addingTimeInterval(-anchor * storyDuration)
        var pausedAt: Date? = nil
        var totalPaused: TimeInterval = 0
        var didPrefetch = anchor >= 0.5
        while progress < 1.0 {
            try? await Task.sleep(nanoseconds: UInt64(tickInterval * 1_000_000_000))
            if Task.isCancelled { return }
            if isPaused {
                if pausedAt == nil { pausedAt = Date() }
                continue
            } else if let p = pausedAt {
                totalPaused += Date().timeIntervalSince(p)
                pausedAt = nil
            }
            let elapsed = Date().timeIntervalSince(startDate) - totalPaused
            progress = min(1.0, elapsed / storyDuration)
            if !didPrefetch, progress >= 0.5 {
                didPrefetch = true
                prefetchNextImage()
            }
        }
        if !Task.isCancelled {
            advance()
        }
    }

    /// Warm URLCache for the next story so AsyncImage renders instantly on tap.
    /// Detached so it doesn't block the progress loop, and de-duped via the
    /// prefetchedURLs set so we don't re-fetch on rewind.
    private func prefetchNextImage() {
        guard currentIndex + 1 < stories.count,
              let url = stories[currentIndex + 1].fullURL,
              !prefetchedURLs.contains(url) else { return }
        prefetchedURLs.insert(url)
        Task.detached { _ = try? await URLSession.shared.data(from: url) }
    }

    private func advance() {
        // Reset progress BEFORE incrementing currentIndex. Otherwise the body
        // re-renders with the new index but stale progress=1.0, and fillFraction
        // paints the new story's bar 100% full for one frame.
        progress = 0
        if currentIndex + 1 < stories.count {
            currentIndex += 1
        } else {
            (onReelComplete ?? onDismiss)()
        }
    }

    private func goBack() {
        if currentIndex == 0 {
            // First story: ask the parent to swipe to the previous person's
            // reel (Instagram tray behavior). If there is no previous person,
            // the parent ignores this and the story stays put.
            if let onRequestPrevious {
                onRequestPrevious()
            } else {
                progress = 0
            }
        } else {
            progress = 0
            currentIndex -= 1
        }
    }
}
