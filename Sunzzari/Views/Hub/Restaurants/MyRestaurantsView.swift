import SwiftUI

struct MyRestaurantsView: View {
    @State private var restaurants: [Restaurant] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    // Filters (all multi-select)
    @State private var beenThereFilter: BeenThereFilter = .all
    @State private var selectedPreferences: Set<Restaurant.Preference> = []
    @State private var selectedLocations: Set<String> = []
    @State private var selectedGoodFor: Set<String> = []

    // Claude AI search
    @State private var claudeQuery: String = ""
    @State private var claudeResults: [String]? = nil
    @State private var isSearching: Bool = false
    @State private var claudeError: String? = nil
    @FocusState private var claudeFieldFocused: Bool

    enum BeenThereFilter: String, CaseIterable {
        case all = "All"; case yes = "Yes"; case no = "No"
    }

    private var hasActiveFilters: Bool {
        beenThereFilter != .all || !selectedPreferences.isEmpty || !selectedLocations.isEmpty || !selectedGoodFor.isEmpty
    }

    private var allGoodForTags: [String] {
        Array(Set(restaurants.flatMap(\.goodFor))).sorted()
    }

    private var allLocationOptions: [String] {
        Array(Set(restaurants.map(\.location).filter { !$0.isEmpty })).sorted()
    }

    private var filtered: [Restaurant] {
        let chipFiltered = restaurants.filter { r in
            let beenOK: Bool
            switch beenThereFilter {
            case .all: beenOK = true
            case .yes: beenOK = r.beenThere
            case .no:  beenOK = !r.beenThere
            }
            let prefOK = selectedPreferences.isEmpty || (r.preference.map { selectedPreferences.contains($0) } ?? false)
            let locOK = selectedLocations.isEmpty || selectedLocations.contains(r.location)
            let gfOK = selectedGoodFor.isEmpty || !selectedGoodFor.isDisjoint(with: r.goodFor)
            return beenOK && prefOK && locOK && gfOK
        }
        // When Claude search is active, preserve its ranking and intersect with chip filters.
        // Dedupe as we go — Claude occasionally emits duplicate IDs which would render
        // as duplicate cards.
        guard let ids = claudeResults else { return chipFiltered }
        let chipSet = Set(chipFiltered.map(\.id))
        let byId = Dictionary(uniqueKeysWithValues: restaurants.map { ($0.id, $0) })
        var seen = Set<String>()
        return ids.compactMap { id in
            guard chipSet.contains(id), seen.insert(id).inserted else { return nil }
            return byId[id]
        }
    }

    var body: some View {
        ZStack {
            Color.sunBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                SerifNavHeader("My Restaurants")

                if isLoading {
                    skeletonView
                } else {
                    claudeSearchBar
                    filterBar
                    Color.white.opacity(0.1).frame(height: 0.5)
                    claudeBanner
                    restaurantList
                }
            }

            // Map FAB — bottom right, below the boop button
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    NavigationLink(destination: RestaurantMapView(restaurants: filtered)) {
                        Image(systemName: "map.fill")
                            .font(.system(size: 16, design: .serif))
                            .foregroundStyle(Color.sunAccent)
                            .padding(14)
                            .background(Color.sunSurface)
                            .clipShape(Circle())
                            .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
                    }
                    .padding(.trailing, 20)
                    .padding(.bottom, 24)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await load() }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    // MARK: - List

    private var restaurantList: some View {
        List {
            if filtered.isEmpty {
                Text("No restaurants match your filters")
                    .font(.system(size: 15, weight: .regular, design: .serif))
                    .foregroundStyle(Color.sunSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 40)
                    .listRowBackground(Color.sunBackground)
                    .listRowSeparator(.hidden)
            } else {
                ForEach(filtered) { r in
                    RestaurantCardView(restaurant: r)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                withAnimation { restaurants.removeAll { $0.id == r.id } }
                                Task { try? await NotionService.shared.archivePage(id: r.id) }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .listRowBackground(Color.sunBackground)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable { await load(force: true) }
    }

    // MARK: - Claude Search Bar

    private var claudeSearchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 14, design: .serif))
                .foregroundStyle(Color.sunAccent)

            TextField("Ask Claude...", text: $claudeQuery)
                .font(.system(size: 14, design: .serif))
                .foregroundStyle(Color.sunText)
                .focused($claudeFieldFocused)
                .submitLabel(.search)
                .onSubmit { Task { await runClaudeSearch() } }

            if isSearching {
                ProgressView().scaleEffect(0.7)
            } else if claudeResults != nil || !claudeQuery.isEmpty {
                Button {
                    clearClaudeSearch()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16, design: .serif))
                        .foregroundStyle(Color.sunSecondary)
                }
            } else if !claudeQuery.isEmpty {
                // no-op placeholder: kept structure for readability
                EmptyView()
            }

            Button {
                Task { await runClaudeSearch() }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 20, design: .serif))
                    .foregroundStyle(claudeQuery.trimmingCharacters(in: .whitespaces).isEmpty
                                     ? Color.sunSecondary
                                     : Color.sunAccent)
            }
            .disabled(claudeQuery.trimmingCharacters(in: .whitespaces).isEmpty || isSearching)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.sunSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }

    @ViewBuilder
    private var claudeBanner: some View {
        if let err = claudeError {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text(err)
                    .font(.system(.caption, design: .serif))
                    .foregroundStyle(Color.sunText)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.red.opacity(0.1))
        } else if let ids = claudeResults {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(Color.sunAccent)
                Text(ids.isEmpty
                     ? "Claude couldn't find a match"
                     : "Claude found \(ids.count) match\(ids.count == 1 ? "" : "es")")
                    .font(.system(.caption, design: .serif, weight: .semibold))
                    .foregroundStyle(Color.sunText)
                Spacer()
                Button("Clear") { clearClaudeSearch() }
                    .font(.system(.caption, design: .serif, weight: .semibold))
                    .foregroundStyle(Color.sunAccent)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.sunAccent.opacity(0.08))
        }
    }

    private func runClaudeSearch() async {
        let trimmed = claudeQuery.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        isSearching = true
        claudeError = nil
        defer { isSearching = false }
        do {
            let ids = try await AnthropicService.shared.searchRestaurants(
                query: trimmed,
                restaurants: restaurants
            )
            claudeResults = ids
            claudeFieldFocused = false
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } catch {
            claudeError = error.localizedDescription
            claudeResults = nil
        }
    }

    private func clearClaudeSearch() {
        claudeQuery = ""
        claudeResults = nil
        claudeError = nil
    }

    // MARK: - Filters

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                // Visited (single-select — mutually exclusive)
                Menu {
                    Button("All") { beenThereFilter = .all }
                    Divider()
                    Button("Yes — Been There") { beenThereFilter = .yes }
                    Button("Not Yet") { beenThereFilter = .no }
                } label: {
                    dropdownLabel(
                        "Visited",
                        value: beenThereFilter == .all ? nil : beenThereFilter.rawValue
                    )
                }

                // Rating (multi-select)
                Menu {
                    ForEach(Restaurant.Preference.allCases, id: \.self) { pref in
                        Button {
                            if selectedPreferences.contains(pref) { selectedPreferences.remove(pref) }
                            else { selectedPreferences.insert(pref) }
                        } label: {
                            Label(pref.rawValue, systemImage: selectedPreferences.contains(pref) ? "checkmark" : "")
                        }
                    }
                    if !selectedPreferences.isEmpty {
                        Divider()
                        Button("Clear", role: .destructive) { selectedPreferences = [] }
                    }
                } label: {
                    dropdownLabel("Rating", value: multiSelectLabel(selectedPreferences.map(\.rawValue)))
                }

                // Location (multi-select)
                Menu {
                    ForEach(allLocationOptions, id: \.self) { loc in
                        Button {
                            if selectedLocations.contains(loc) { selectedLocations.remove(loc) }
                            else { selectedLocations.insert(loc) }
                        } label: {
                            Label(loc, systemImage: selectedLocations.contains(loc) ? "checkmark" : "")
                        }
                    }
                    if !selectedLocations.isEmpty {
                        Divider()
                        Button("Clear", role: .destructive) { selectedLocations = [] }
                    }
                } label: {
                    dropdownLabel("Location", value: multiSelectLabel(Array(selectedLocations)))
                }

                // Good For (multi-select)
                Menu {
                    ForEach(allGoodForTags, id: \.self) { tag in
                        Button {
                            if selectedGoodFor.contains(tag) { selectedGoodFor.remove(tag) }
                            else { selectedGoodFor.insert(tag) }
                        } label: {
                            Label(tag, systemImage: selectedGoodFor.contains(tag) ? "checkmark" : "")
                        }
                    }
                    if !selectedGoodFor.isEmpty {
                        Divider()
                        Button("Clear", role: .destructive) { selectedGoodFor = [] }
                    }
                } label: {
                    dropdownLabel("Good For", value: multiSelectLabel(Array(selectedGoodFor)))
                }

                // Clear All
                if hasActiveFilters {
                    Button {
                        clearAll()
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .semibold, design: .serif))
                            Text("Clear All")
                                .font(.system(size: 13, design: .serif))
                        }
                        .foregroundStyle(Color.sunSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1))
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 10)
    }

    private func clearAll() {
        beenThereFilter = .all
        selectedPreferences = []
        selectedLocations = []
        selectedGoodFor = []
    }

    private func multiSelectLabel(_ values: [String]) -> String? {
        switch values.count {
        case 0: return nil
        case 1: return values[0]
        default: return "\(values.count) selected"
        }
    }

    private func dropdownLabel(_ title: String, value: String?) -> some View {
        HStack(spacing: 4) {
            Text(value ?? title)
                .font(.system(size: 13, weight: value != nil ? .semibold : .regular, design: .serif))
                .foregroundStyle(value != nil ? Color.sunAccent : Color.sunSecondary)
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.system(size: 10, design: .serif))
                .foregroundStyle(value != nil ? Color.sunAccent : Color.sunSecondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(value != nil ? Color.sunAccent.opacity(0.12) : Color.sunSurface)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(
            value != nil ? Color.sunAccent.opacity(0.8) : Color.white.opacity(0.15),
            lineWidth: 1
        ))
    }

    // MARK: - Skeleton

    private var skeletonView: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(0..<5, id: \.self) { _ in SkeletonEntryCard().padding(.horizontal, 16) }
            }
            .padding(.vertical, 16)
        }
    }

    // MARK: - Load

    private func load(force: Bool = false) async {
        // Show disk cache immediately — no skeleton flash on repeat opens
        if !force, restaurants.isEmpty,
           let cached = NotionService.shared.restaurantsDiskCache() {
            restaurants = cached
            isLoading = false
        }

        // Fetch fresh data (memory cache if within 5 min, otherwise network)
        do {
            let fresh = try await NotionService.shared.fetchRestaurants(force: force)
            restaurants = fresh
        } catch is CancellationError {
            return
        } catch let urlErr as URLError where urlErr.code == .cancelled {
            return
        } catch {
            if restaurants.isEmpty { errorMessage = error.localizedDescription }
        }
        isLoading = false
    }
}
