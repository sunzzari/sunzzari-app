import SwiftUI

struct SearchView: View {
    @State private var query: String = ""
    @State private var bestOf: [BestOfEntry] = []
    @State private var isLoading = true

    private var trimmed: String { query.trimmingCharacters(in: .whitespaces) }

    private var filteredBestOf: [BestOfEntry] {
        guard !trimmed.isEmpty else { return [] }
        return bestOf.filter {
            $0.category != .improvements &&
            ($0.entry.localizedCaseInsensitiveContains(trimmed) ||
             $0.notes.localizedCaseInsensitiveContains(trimmed) ||
             $0.category.rawValue.localizedCaseInsensitiveContains(trimmed))
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.sunBackground.ignoresSafeArea()
                content
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.large)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .searchable(text: $query, prompt: "Search Best Of...")
        }
        .task { await loadAll() }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(0..<5, id: \.self) { _ in
                        SkeletonEntryCard().padding(.horizontal, 16)
                    }
                }
                .padding(.vertical, 16)
            }
        } else if trimmed.isEmpty {
            promptState
        } else if filteredBestOf.isEmpty {
            EmptyStateView(
                systemImage: "magnifyingglass",
                title: "No results",
                subtitle: "Try different keywords."
            )
        } else {
            resultsList
        }
    }

    private var resultsList: some View {
        List {
            Section {
                ForEach(filteredBestOf) { entry in
                    BestOfEntryCard(entry: entry)
                        .listRowBackground(Color.sunBackground)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                }
            } header: {
                sectionLabel("BEST OF · \(filteredBestOf.count)")
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private var promptState: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 42, design: .serif))
                .foregroundStyle(Color.sunSecondary.opacity(0.35))
            Text("Search across Best Of")
                .font(.subheadline)
                .foregroundStyle(Color.sunSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold, design: .serif))
            .tracking(1)
            .foregroundStyle(Color.sunSecondary)
            .textCase(nil)
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
    }

    private func loadAll(force: Bool = false) async {
        isLoading = true
        do {
            bestOf = try await NotionService.shared.fetchBestOf(force: force)
        } catch is CancellationError {
            // tab switch cancelled — keep existing data
        } catch let urlErr as URLError where urlErr.code == .cancelled {
            // network cancelled — keep existing data
        } catch {
            bestOf = []
        }
        isLoading = false
    }
}
