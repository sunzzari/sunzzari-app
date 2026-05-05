import SwiftUI

/// Auto-promoted on Dec 31 (handled by StoriesView), accessible any time from
/// Archive. Plays through the year's stories as a single montage.
///
/// IG-parity gestures: tap right to skip a story, tap left to rewind, hold
/// anywhere to pause, drag down to dismiss. Author and date overlay.
struct YearRecapView: View {
    let year: Int
    let stories: [StoryPost]

    @State private var currentIndex: Int = 0
    @State private var progress: Double = 0
    @State private var isPaused: Bool = false
    @State private var dragOffset: CGFloat = 0
    @Environment(\.dismiss) private var dismiss

    private let storyDuration: TimeInterval = 3.5
    private let tickInterval: TimeInterval = 0.05

    private var sortedStories: [StoryPost] {
        stories.sorted { $0.postedAt < $1.postedAt }
    }

    private var currentStory: StoryPost? {
        sortedStories.indices.contains(currentIndex) ? sortedStories[currentIndex] : nil
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if sortedStories.isEmpty {
                Text("No stories to recap for \(String(year))")
                    .font(.system(.subheadline, design: .serif))
                    .foregroundStyle(.white.opacity(0.7))
            } else if let currentStory {
                AsyncImage(url: currentStory.fullURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        Color.black
                    }
                }
                .ignoresSafeArea()

                // Tap zones — pushed below the progress bars at the top so the
                // bars themselves are not tappable.
                VStack(spacing: 0) {
                    Color.clear.frame(height: 60)
                    HStack(spacing: 0) {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { goBack() }
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { advance() }
                    }
                }

                VStack {
                    HStack(spacing: 4) {
                        ForEach(sortedStories.indices, id: \.self) { i in
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.white.opacity(0.25))
                                    Capsule()
                                        .fill(Color.white)
                                        .frame(width: geo.size.width * fillFraction(for: i))
                                }
                            }
                            .frame(height: 2)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)

                    Spacer()

                    VStack(spacing: 4) {
                        Text(currentStory.person.rawValue)
                            .font(.system(.subheadline, design: .serif, weight: .semibold))
                            .foregroundStyle(.white)
                        Text(monthDayString(for: currentStory.postedAt))
                            .font(.system(.caption, design: .serif))
                            .foregroundStyle(.white.opacity(0.8))
                        if !currentStory.caption.isEmpty {
                            Text(currentStory.caption)
                                .font(.system(.body, design: .serif))
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                                .padding(.top, 6)
                        }
                    }
                    .padding(.bottom, 60)
                }
            }
        }
        .offset(y: dragOffset)
        .gesture(
            DragGesture()
                .onChanged { value in
                    if value.translation.height > 0 {
                        dragOffset = value.translation.height
                    }
                }
                .onEnded { value in
                    if value.translation.height > 120 {
                        dismiss()
                    } else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                            dragOffset = 0
                        }
                    }
                }
        )
        .onLongPressGesture(minimumDuration: 0.2, maximumDistance: 50) {
        } onPressingChanged: { pressing in
            isPaused = pressing
        }
        .navigationTitle("\(String(year)) Recap")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
                    .foregroundStyle(.white)
            }
        }
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(.black.opacity(0.3), for: .navigationBar)
        .task(id: currentIndex) {
            await runProgressLoop()
        }
    }

    private func fillFraction(for i: Int) -> Double {
        if i < currentIndex { return 1.0 }
        if i == currentIndex { return progress }
        return 0
    }

    /// Wall-clock anchored progress with pause-time accumulator (matches the
    /// player's clock so behavior under load is consistent across views).
    private func runProgressLoop() async {
        progress = 0
        let startDate = Date()
        var pausedAt: Date? = nil
        var totalPaused: TimeInterval = 0
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
        }
        if !Task.isCancelled {
            advance()
        }
    }

    private func advance() {
        progress = 0
        if currentIndex + 1 < sortedStories.count {
            currentIndex += 1
        } else {
            dismiss()
        }
    }

    private func goBack() {
        if currentIndex == 0 {
            progress = 0
        } else {
            progress = 0
            currentIndex -= 1
        }
    }

    private func monthDayString(for date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMMM d"
        return f.string(from: date)
    }
}
