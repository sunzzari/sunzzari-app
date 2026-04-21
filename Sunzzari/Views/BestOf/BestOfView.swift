import SwiftUI

struct BestOfView: View {
    @State private var entries: [BestOfEntry] = []
    @State private var isLoading = true
    @State private var selectedCategory: BestOfEntry.Category? = nil
    @State private var showAddEntry = false
    @State private var errorMessage: String?
    @State private var expandedYears: Set<Int> = []
    @State private var selectedEntry: BestOfEntry? = nil
    @State private var entryToEdit: BestOfEntry? = nil
    @Namespace private var cardNamespace

    private let currentYear = 2026

    private var pastYears: [Int] {
        Array(Set(entries.map(\.year)).filter { $0 < currentYear && $0 != 1996 }).sorted(by: >)
    }

    private func entriesFor(year: Int) -> [BestOfEntry] {
        entries.filter {
            $0.year == year &&
            (selectedCategory == nil || $0.category == selectedCategory)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.sunBackground.ignoresSafeArea()

                VStack(spacing: 0) {
                    SerifNavHeader("Best Of", showsBack: false)

                    if isLoading {
                        skeletonView
                    } else {
                        categoryFilter.padding(.vertical, 10)
                        Color.white.opacity(0.1).frame(height: 0.5)
                        entryList
                    }
                }

                if selectedEntry == nil { fab }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .overlay {
            if let entry = selectedEntry {
                ZStack {
                    Color.black.opacity(0.55)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                selectedEntry = nil
                            }
                        }
                    BestOfDetailView(entry: entry, namespace: cardNamespace, onDismiss: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            selectedEntry = nil
                        }
                    }, onEdit: {
                        let captured = entry
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            selectedEntry = nil
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            entryToEdit = captured
                        }
                    })
                }
                .transition(.identity)
            }
        }
        .sheet(isPresented: $showAddEntry, onDismiss: { Task { await load() } }) {
            AddEntryView()
        }
        .sheet(item: $entryToEdit) { entry in
            EditEntryView(entry: entry) { updated in
                if let idx = entries.firstIndex(where: { $0.id == updated.id }) {
                    entries[idx] = updated
                }
            }
        }
        .task { await load() }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    // MARK: - Skeleton

    private var skeletonView: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(0..<6, id: \.self) { _ in
                    SkeletonEntryCard().padding(.horizontal, 16)
                }
            }
            .padding(.vertical, 16)
        }
    }

    // MARK: - Entry list

    private var entryList: some View {
        List {
            Section {
                let current = entriesFor(year: currentYear)
                if current.isEmpty {
                    Text("Nothing yet for 2026 — add your first entry!")
                        .font(.system(size: 15, weight: .regular, design: .serif))
                        .foregroundStyle(Color.sunSecondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 20)
                        .listRowBackground(Color.sunBackground)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                } else {
                    ForEach(current) { entry in entryRow(entry) }
                }
            } header: { yearHeader(currentYear, collapsible: false) }

            ForEach(pastYears, id: \.self) { year in
                Section {
                    if expandedYears.contains(year) {
                        let yearEntries = entriesFor(year: year)
                        if yearEntries.isEmpty {
                            Text("No entries in this category")
                                .font(.system(size: 15, weight: .regular, design: .serif))
                                .foregroundStyle(Color.sunSecondary)
                                .listRowBackground(Color.sunBackground)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        } else {
                            ForEach(yearEntries) { entry in entryRow(entry) }
                        }
                    }
                } header: { yearHeader(year, collapsible: true) }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable { await load(force: true) }
    }

    @ViewBuilder
    private func entryRow(_ entry: BestOfEntry) -> some View {
        BestOfEntryCard(entry: entry)
            .matchedGeometryEffect(id: entry.id, in: cardNamespace)
            .opacity(selectedEntry?.id == entry.id ? 0 : 1)
            .onTapGesture {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    selectedEntry = entry
                }
            }
            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    entryToEdit = entry
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .tint(.orange)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    withAnimation { entries.removeAll { $0.id == entry.id } }
                    Task { try? await NotionService.shared.archivePage(id: entry.id) }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            .listRowBackground(Color.sunBackground)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
    }

    // MARK: - Section headers

    private func yearHeader(_ year: Int, collapsible: Bool) -> some View {
        Button {
            guard collapsible else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.easeInOut(duration: 0.2)) {
                if expandedYears.contains(year) { expandedYears.remove(year) }
                else { expandedYears.insert(year) }
            }
        } label: {
            HStack(spacing: 0) {
                // Amber left accent bar — matches travel map group header style
                Rectangle()
                    .fill(Color.sunAccent)
                    .frame(width: 3)

                HStack(spacing: 8) {
                    Text(String(year))
                        .font(.system(size: 14, weight: .bold, design: .serif))
                        .fontDesign(.serif)
                        .foregroundStyle(Color.sunText)

                    let count = entries.filter { $0.year == year }.count
                    Text("\(count)")
                        .font(.system(size: 10, weight: .bold, design: .serif))
                        .foregroundStyle(Color.sunAccent)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.sunAccent.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 4))

                    Spacer()

                    if collapsible {
                        Image(systemName: expandedYears.contains(year) ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .semibold, design: .serif))
                            .foregroundStyle(Color.sunSecondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .background(Color.white.opacity(0.05))
            .textCase(nil)
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
    }

    // MARK: - Category filter

    private var categoryFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button {
                    selectedCategory = nil
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Text("ALL")
                        .font(.system(size: 10, weight: .bold, design: .serif))
                        .tracking(0.8)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(selectedCategory == nil ? Color.sunAccent.opacity(0.12) : Color.clear)
                        .foregroundStyle(selectedCategory == nil ? Color.sunAccent : Color.sunSecondary)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(selectedCategory == nil ? Color.sunAccent.opacity(1) : Color.white.opacity(0.2), lineWidth: 1))
                        .shadow(color: selectedCategory == nil ? Color.sunAccent.opacity(0.4) : .clear, radius: 6, y: 0)
                }
                ForEach(BestOfEntry.Category.allCases, id: \.self) { cat in
                    Button {
                        selectedCategory = cat
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        CategoryChip(label: cat.rawValue, colorHex: cat.colorHex, isSelected: selectedCategory == cat)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - FAB

    private var fab: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Button { showAddEntry = true } label: {
                    Image(systemName: "plus")
                        .font(.system(.title2, design: .serif, weight: .semibold))
                        .foregroundStyle(Color.sunBackground)
                        .frame(width: 56, height: 56)
                        .background(Color.sunAccent)
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
                }
                .padding(.trailing, 20)
                .padding(.bottom, 8)
            }
        }
    }

    // MARK: - Load

    private func load(force: Bool = false) async {
        // Stale-while-revalidate: serve disk cache instantly, refresh in background
        if !force, let cached = NotionService.shared.bestOfDiskCache() {
            entries = cached
            isLoading = false
            do {
                let fresh = try await NotionService.shared.fetchBestOf(force: true)
                entries = fresh
            } catch is CancellationError {
            } catch let urlErr as URLError where urlErr.code == .cancelled {
            } catch { /* silently fail — user already sees cached data */ }
            return
        }
        // No disk cache (first-ever launch) or pull-to-refresh
        isLoading = true
        defer { isLoading = false }
        do {
            entries = try await NotionService.shared.fetchBestOf(force: force)
        } catch is CancellationError {
            return
        } catch let urlErr as URLError where urlErr.code == .cancelled {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
