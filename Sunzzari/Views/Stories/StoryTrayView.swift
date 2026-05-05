import SwiftUI

/// Wraps the per-person `StoryPlayerView` in a paged `TabView` so swiping
/// horizontally moves between persons (Instagram tray gesture) and end-of-reel
/// auto-advance animates without a fullScreenCover dismiss/re-present flicker.
///
/// Only the visible player runs its timer (gated by `isActive`), so a paged-but-
/// preloaded sibling tab does not race the visible reel forward.
struct StoryTrayView: View {
    let persons: [StoryPost.Person]
    let reelFor: (StoryPost.Person) -> [StoryPost]
    let onDismiss: () -> Void

    @State private var currentPerson: StoryPost.Person

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
        TabView(selection: $currentPerson) {
            ForEach(persons, id: \.self) { person in
                StoryPlayerView(
                    stories: reelFor(person),
                    person: person,
                    onDismiss: onDismiss,
                    onReelComplete: { advance(after: person) },
                    onRequestPrevious: { back(from: person) },
                    isActive: currentPerson == person
                )
                .tag(person)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .ignoresSafeArea()
        .background(Color.black)
        .statusBarHidden(true)
    }

    private func advance(after person: StoryPost.Person) {
        guard let idx = persons.firstIndex(of: person) else {
            onDismiss()
            return
        }
        if idx + 1 < persons.count {
            withAnimation(.easeInOut(duration: 0.25)) {
                currentPerson = persons[idx + 1]
            }
        } else {
            onDismiss()
        }
    }

    private func back(from person: StoryPost.Person) {
        guard let idx = persons.firstIndex(of: person), idx > 0 else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            currentPerson = persons[idx - 1]
        }
    }
}
