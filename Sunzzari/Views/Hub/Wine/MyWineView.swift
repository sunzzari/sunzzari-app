import SwiftUI

struct MyWineView: View {
    @State private var wines: [Wine] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    // Filters & Sort
    @State private var selectedType: Wine.WineType? = nil
    @State private var selectedLocations: Set<Wine.PurchaseLocation> = []
    @State private var cookingOnly = false
    @State private var sortOrder: WineSortOrder = .default

    enum WineSortOrder: String, CaseIterable {
        case `default` = "Default"
        case highToLow = "Rating: High → Low"
        case lowToHigh = "Rating: Low → High"
    }

    private var hasActiveFilters: Bool {
        selectedType != nil || !selectedLocations.isEmpty || cookingOnly || sortOrder != .default
    }

    private var filtered: [Wine] {
        let base = wines.filter { w in
            let typeOK = selectedType == nil || w.wineType == selectedType
            let locOK = selectedLocations.isEmpty || (w.purchaseLocation.map { selectedLocations.contains($0) } ?? false)
            let cookOK = !cookingOnly || w.useForCooking
            return typeOK && locOK && cookOK
        }
        switch sortOrder {
        case .default:   return base
        case .highToLow: return base.sorted { ($0.rating?.stars ?? 0) > ($1.rating?.stars ?? 0) }
        case .lowToHigh: return base.sorted { ($0.rating?.stars ?? 0) < ($1.rating?.stars ?? 0) }
        }
    }

    var body: some View {
        ZStack {
            Color.sunBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                SerifNavHeader("My Wine")

                if isLoading {
                    skeletonView
                } else {
                    filterBar
                    Color.white.opacity(0.1).frame(height: 0.5)
                    wineList
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await load() }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private var wineList: some View {
        List {
            if filtered.isEmpty {
                Text("No wines match your filters")
                    .font(.system(size: 15, weight: .regular, design: .serif))
                    .foregroundStyle(Color.sunSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 40)
                    .listRowBackground(Color.sunBackground)
                    .listRowSeparator(.hidden)
            } else {
                ForEach(filtered) { w in
                    WineCardView(wine: w)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                withAnimation { wines.removeAll { $0.id == w.id } }
                                Task { try? await NotionService.shared.archivePage(id: w.id) }
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

    private var filterBar: some View {
        VStack(spacing: 0) {
            // Row 1: Wine Type pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Wine.WineType.allCases, id: \.self) { type in
                        Button {
                            selectedType = selectedType == type ? nil : type
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } label: {
                            CategoryChip(label: type.rawValue, colorHex: type.colorHex, isSelected: selectedType == type)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.vertical, 10)

            Color.white.opacity(0.06).frame(height: 0.5)

            // Row 2: Dropdowns + Cooking pill + Clear All
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    // Where to Buy (multi-select)
                    Menu {
                        ForEach(Wine.PurchaseLocation.allCases, id: \.self) { loc in
                            Button {
                                if selectedLocations.contains(loc) { selectedLocations.remove(loc) }
                                else { selectedLocations.insert(loc) }
                            } label: {
                                Label(loc.rawValue, systemImage: selectedLocations.contains(loc) ? "checkmark" : "")
                            }
                        }
                        if !selectedLocations.isEmpty {
                            Divider()
                            Button("Clear", role: .destructive) { selectedLocations = [] }
                        }
                    } label: {
                        dropdownLabel("Where to Buy", value: multiSelectLabel(selectedLocations.map(\.rawValue)))
                    }

                    // Sort by Rating (single-select)
                    Menu {
                        Button("Default") { sortOrder = .default }
                        Divider()
                        Button("High → Low") { sortOrder = .highToLow }
                        Button("Low → High") { sortOrder = .lowToHigh }
                    } label: {
                        dropdownLabel(
                            "Sort",
                            value: sortOrder == .default ? nil : sortOrder == .highToLow ? "⭐ High → Low" : "⭐ Low → High"
                        )
                    }

                    // Cooking pill
                    Button {
                        cookingOnly.toggle()
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Text("Cooking")
                            .font(.system(size: 13, weight: cookingOnly ? .semibold : .regular, design: .serif))
                            .foregroundStyle(cookingOnly ? Color.sunAccent : Color.sunSecondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(cookingOnly ? Color.sunAccent.opacity(0.12) : Color.sunSurface)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(
                                cookingOnly ? Color.sunAccent.opacity(0.8) : Color.white.opacity(0.15),
                                lineWidth: 1
                            ))
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
    }

    private func clearAll() {
        selectedType = nil
        selectedLocations = []
        cookingOnly = false
        sortOrder = .default
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

    private var skeletonView: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(0..<5, id: \.self) { _ in SkeletonEntryCard().padding(.horizontal, 16) }
            }
            .padding(.vertical, 16)
        }
    }

    private func load(force: Bool = false) async {
        // Show disk cache immediately — no skeleton flash on repeat opens
        if !force, wines.isEmpty,
           let cached = NotionService.shared.winesDiskCache() {
            wines = cached
            isLoading = false
        }

        // Fetch fresh data (memory cache if within 5 min, otherwise network)
        do {
            let fresh = try await NotionService.shared.fetchWines(force: force)
            wines = fresh
        } catch is CancellationError {
            return
        } catch let urlErr as URLError where urlErr.code == .cancelled {
            return
        } catch {
            if wines.isEmpty { errorMessage = error.localizedDescription }
        }
        isLoading = false
    }
}
