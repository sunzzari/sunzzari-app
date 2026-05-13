import SwiftUI

/// Wraps the per-person `StoryPlayerView` in a paged `TabView` so swiping
/// horizontally moves between persons (Instagram tray gesture) and end-of-reel
/// auto-advance animates without a fullScreenCover dismiss/re-present flicker.
///
/// Only the visible player runs its timer (gated by `isActive`), so a paged-but-
/// preloaded sibling tab does not race the visible reel forward.
///
/// When the LAST person's reel finishes, instead of dismissing back to Today
/// we freeze on the final frame and show a Replay overlay. Replay resets to
/// the first person's first story; Close exits to Today.
struct StoryTrayView: View {
    let persons: [StoryPost.Person]
    let reelFor: (StoryPost.Person) -> [StoryPost]
    let onDismiss: () -> Void

    @State private var currentPerson: StoryPost.Person
    @State private var showReplay: Bool = false
    /// Bumped on Replay tap. Used as `.id()` on the TabView so SwiftUI rebuilds
    /// every child StoryPlayerView, which is the only way to reset their
    /// `@State currentIndex` and `progress` from outside.
    @State private var replayNonce: UUID = UUID()

    init(
        persons: [StoryPost.Person],
        startingPerson: StoryPost.Person,
        reelFor: @escaping (StoryPost.Person) -> [StoryPost],
        onDismiss: @escaping () -> Void
    ) {
        self.persons = persons
        self.reelFor = reelFor
        self.onDismiss = onDismiss
        // If the starting person somehow isn't in the active list (race), fall
        // back to the first active person so we never present an empty tab.
        _currentPerson = State(initialValue: persons.contains(startingPerson)
                               ? startingPerson
                               : (persons.first ?? startingPerson))
    }

    var body: some View {
        ZStack {
            TabView(selection: $currentPerson) {
                ForEach(persons, id: \.self) { person in
                    StoryPlayerView(
                        stories: reelFor(person),
                        person: person,
                        onDismiss: onDismiss,
                        onReelComplete: { advance(after: person) },
                        onRequestPrevious: { back(from: person) },
                        // Pause the visible player while the replay overlay is up
                        // so its progress task doesn't keep ticking past the end.
                        isActive: currentPerson == person && !showReplay
                    )
                    .tag(person)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .id(replayNonce)

            if showReplay {
                replayOverlay
            }
        }
        .ignoresSafeArea()
        .background(Color.black)
        .statusBarHidden(true)
    }

    private var replayOverlay: some View {
        // Keep the last frame fully visible behind the controls — no full-screen
        // dim. A small glass-blur Replay button sits center, Close sits below.
        VStack(spacing: 14) {
            Button(action: replay) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Replay")
                        .font(.system(.subheadline, design: .serif, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.4), lineWidth: 0.5))
            }
            .accessibilityLabel("Replay stories")

            Button(action: onDismiss) {
                Text("Close")
                    .font(.system(.footnote, design: .serif, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }
            .accessibilityLabel("Close stories")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .transition(.opacity)
    }

    private func advance(after person: StoryPost.Person) {
        guard let idx = persons.firstIndex(of: person) else {
            showReplay = true
            return
        }
        if idx + 1 < persons.count {
            withAnimation(.easeInOut(duration: 0.25)) {
                currentPerson = persons[idx + 1]
            }
        } else {
            withAnimation(.easeInOut(duration: 0.2)) {
                showReplay = true
            }
        }
    }

    private func back(from person: StoryPost.Person) {
        guard let idx = persons.firstIndex(of: person), idx > 0 else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            currentPerson = persons[idx - 1]
        }
    }

    private func replay() {
        currentPerson = persons.first ?? currentPerson
        // New UUID forces every StoryPlayerView to rebuild from scratch, which
        // resets currentIndex/progress to 0 and restarts the progress task.
        replayNonce = UUID()
        withAnimation(.easeInOut(duration: 0.2)) {
            showReplay = false
        }
    }
}
