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
        restaurants.filter { r in
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
    }

    var body: some View {
        ZStack {
            Color.sunBackground.ignoresSafeArea()

            if isLoading {
                skeletonView
            } else {
                VStack(spacing: 0) {
                    filterBar
                    Color.white.opacity(0.1).frame(height: 0.5)
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
                            .font(.system(size: 16))
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
        .navigationTitle("My Restaurants")
        .navigationBarTitleDisplayMode(.large)
            .toolbarColorScheme(.dark, for: .navigationBar)
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
                    .font(.subheadline)
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
                                .font(.system(size: 10, weight: .semibold))
                            Text("Clear All")
                                .font(.system(size: 13))
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
                .font(.system(size: 13, weight: value != nil ? .semibold : .regular))
                .foregroundStyle(value != nil ? Color.sunAccent : Color.sunSecondary)
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.system(size: 10))
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
