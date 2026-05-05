import SwiftUI

struct StoryArchiveView: View {
    @State private var stories: [StoryPost] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var year: Int = Calendar(identifier: .gregorian).component(.year, from: Date())
    @State private var showRecap = false

    private let cal = Calendar(identifier: .gregorian)

    private var monthsWithStories: [(monthIndex: Int, items: [StoryPost])] {
        let groups = Dictionary(grouping: stories) { cal.component(.month, from: $0.postedAt) }
        return groups
            .sorted { $0.key > $1.key }
            .map { (monthIndex: $0.key, items: $0.value.sorted { $0.postedAt > $1.postedAt }) }
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
                        LazyVStack(alignment: .leading, spacing: 24) {
                            ForEach(monthsWithStories, id: \.monthIndex) { month in
                                monthSection(month: month.monthIndex, items: month.items)
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

    private func monthSection(month: Int, items: [StoryPost]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(monthName(month).uppercased())
                .font(.system(size: 11, weight: .bold, design: .serif))
                .tracking(1.2)
                .foregroundStyle(Color.sunSecondary)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                ForEach(items) { post in
                    thumbnail(post)
                }
            }
        }
    }

    private func thumbnail(_ post: StoryPost) -> some View {
        ZStack(alignment: .bottomLeading) {
            AsyncImage(url: post.thumbnailURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    Color.sunSurface
                }
            }
            .frame(height: 120)
            .frame(maxWidth: .infinity)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Text(post.person.rawValue)
                .font(.system(size: 9, weight: .semibold, design: .serif))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color(hex: post.person.colorHex).opacity(0.85))
                .clipShape(Capsule())
                .padding(6)
        }
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
