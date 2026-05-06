import SwiftUI

struct StoryArchiveView: View {
    @State private var stories: [StoryPost] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var year: Int = Calendar(identifier: .gregorian).component(.year, from: Date())
    @State private var showRecap = false
    @State private var stackPayload: StackPlayerPayload? = nil

    private let cal = Calendar(identifier: .gregorian)

    /// Stories grouped first by calendar day (newest day first), then by person
    /// within each day. Each (day, person) bucket renders as a visual stack of
    /// overlapping cards. Tapping a stack opens the bucket's reel in the player.
    private var daysWithStacks: [(day: Date, stacks: [(person: StoryPost.Person, items: [StoryPost])])] {
        let dayGroups = Dictionary(grouping: stories) { cal.startOfDay(for: $0.postedAt) }
        return dayGroups
            .sorted { $0.key > $1.key }
            .map { (day, dayItems) in
                let personGroups = Dictionary(grouping: dayItems) { $0.person }
                let stacks = personGroups
                    .map { (person: $0.key, items: $0.value.sorted { $0.postedAt > $1.postedAt }) }
                    .sorted { $0.items.first?.postedAt ?? .distantPast > $1.items.first?.postedAt ?? .distantPast }
                return (day: day, stacks: stacks)
            }
    }

    var body: some View {
        ZStack {
            Color.sunBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                yearHeader

                if isLoading && stories.isEmpty {
                    Spacer()
                    ProgressView().tint(.sunAccent)
                    Spacer()
                } else if stories.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 28) {
                            ForEach(daysWithStacks, id: \.day) { day in
                                daySection(day: day.day, stacks: day.stacks)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 60)
                    }
                }
            }
        }
        .navigationTitle("Archive")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(Color.sunSurface, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showRecap = true
                } label: {
                    Label("Recap", systemImage: "sparkles")
                        .foregroundStyle(Color.sunAccent)
                }
                .disabled(stories.isEmpty)
            }
        }
        .navigationDestination(isPresented: $showRecap) {
            YearRecapView(year: year, stories: stories)
        }
        .fullScreenCover(item: $stackPayload) { payload in
            StoryPlayerView(
                stories: payload.stories,
                person: payload.person,
                onDismiss: { stackPayload = nil },
                onReelComplete: { stackPayload = nil },
                onRequestPrevious: {},
                isActive: true
            )
            .ignoresSafeArea()
            .background(Color.black)
            .statusBarHidden(true)
        }
        .alert("Couldn't load archive", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .task(id: year) { await load() }
    }

    private var yearHeader: some View {
        HStack(spacing: 14) {
            Button { year -= 1 } label: {
                Image(systemName: "chevron.left")
                    .font(.system(.body, design: .serif))
                    .foregroundStyle(Color.sunAccent)
                    .padding(8)
            }
            Text(String(year))
                .font(.system(.title3, design: .serif, weight: .semibold))
                .foregroundStyle(Color.sunText)
            Button { year += 1 } label: {
                Image(systemName: "chevron.right")
                    .font(.system(.body, design: .serif))
                    .foregroundStyle(Color.sunAccent)
                    .padding(8)
            }
            Spacer()
            Text("\(stories.count) photos")
                .font(.system(.caption, design: .serif))
                .foregroundStyle(Color.sunSecondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.sunSurface)
    }

    private func daySection(day: Date, stacks: [(person: StoryPost.Person, items: [StoryPost])]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(dayLabel(day).uppercased())
                .font(.system(size: 11, weight: .bold, design: .serif))
                .tracking(1.2)
                .foregroundStyle(Color.sunSecondary)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 2), spacing: 16) {
                ForEach(stacks, id: \.person) { stack in
                    Button {
                        stackPayload = StackPlayerPayload(stories: stack.items, person: stack.person)
                    } label: {
                        stackCard(person: stack.person, items: stack.items)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// Visual deck: cover image on top with a single backing card behind to
    /// imply depth. Backing renders at a fixed offset whenever count > 1, so
    /// the stack's visual footprint is identical across cells regardless of
    /// how many photos sit in the bucket -- the count number lives in the
    /// chip, not in the stack height. Person color tints the border + chip.
    private func stackCard(person: StoryPost.Person, items: [StoryPost]) -> some View {
        let cover = items.first
        let count = items.count
        let personColor = Color(hex: person.colorHex)

        return ZStack(alignment: .bottomLeading) {
            if count > 1 {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.sunSurface)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(personColor.opacity(0.4), lineWidth: 1))
                    .offset(x: 4, y: 4)
                    .frame(height: 160)
            }

            // Cover card
            ZStack(alignment: .bottomLeading) {
                AsyncImage(url: cover?.thumbnailURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        Color.sunSurface
                    }
                }
                .frame(height: 160)
                .frame(maxWidth: .infinity)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(personColor.opacity(0.7), lineWidth: 1.5)
                )

                HStack(spacing: 6) {
                    Text(person.rawValue)
                        .font(.system(size: 10, weight: .semibold, design: .serif))
                        .foregroundStyle(.white)
                    if count > 1 {
                        Text("\(count)")
                            .font(.system(size: 10, weight: .bold, design: .serif))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.black.opacity(0.55))
                            .clipShape(Capsule())
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(personColor.opacity(0.85))
                .clipShape(Capsule())
                .padding(8)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 168)
    }

    private func dayLabel(_ day: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        return formatter.string(from: day)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle")
                .font(.system(size: 44, design: .serif))
                .foregroundStyle(Color.sunSecondary)
            Text("No stories yet for \(String(year))")
                .font(.system(.subheadline, design: .serif))
                .foregroundStyle(Color.sunSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private func monthName(_ index: Int) -> String {
        let symbols = DateFormatter().monthSymbols ?? []
        guard symbols.indices.contains(index - 1) else { return "" }
        return symbols[index - 1]
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            stories = try await NotionService.shared.fetchArchiveStories(year: year)
        } catch is CancellationError {
        } catch let err as URLError where err.code == .cancelled {
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct StackPlayerPayload: Identifiable {
    let id: String
    let stories: [StoryPost]
    let person: StoryPost.Person

    init(stories: [StoryPost], person: StoryPost.Person) {
        self.id = "\(person.rawValue)-\(stories.first?.id ?? UUID().uuidString)"
        self.stories = stories
        self.person = person
    }
}
