import SwiftUI

struct TodayView: View {
    @State private var bestMomentsToday: [BestOfEntry] = []
    @State private var otherToday: [BestOfEntry] = []
    @State private var fallbackEntry: BestOfEntry? = nil
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isNewYearsDay = false

    @State private var selectedEntry: BestOfEntry? = nil
    @State private var entryToEdit: BestOfEntry? = nil
    @Namespace private var cardNamespace

    private var hasToday: Bool { !bestMomentsToday.isEmpty || !otherToday.isEmpty }
    private var todayCount: Int { bestMomentsToday.count + otherToday.count }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.sunBackground.ignoresSafeArea()

                if isLoading {
                    skeletonView
                } else if isNewYearsDay {
                    List {
                        Section { newYearView } header: { dateHeader }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                } else {
                    List {
                        Section {
                            if hasToday {
                                // Tier 1: Best Moments for today (highest priority)
                                ForEach(bestMomentsToday) { entry in
                                    entryRow(entry)
                                }
                                // Tier 2: Other categories for today
                                ForEach(otherToday) { entry in
                                    entryRow(entry)
                                }
                            } else if let entry = fallbackEntry {
                                // Tier 3: Random unassigned fallback
                                fallbackCard(entry)
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
                                    .listRowBackground(Color.sunBackground)
                                    .listRowSeparator(.hidden)
                                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
                            } else {
                                Text("Nothing to show today — check back later!")
                                    .font(.subheadline)
                                    .foregroundStyle(Color.sunSecondary)
                                    .padding(.vertical, 20)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .listRowBackground(Color.sunBackground)
                                    .listRowSeparator(.hidden)
                            }
                        } header: {
                            dateHeader
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .refreshable { await load(force: true) }
                }
            }
            .navigationTitle("Today")
            .navigationBarTitleDisplayMode(.large)
            .toolbarColorScheme(.dark, for: .navigationBar)
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
        .sheet(item: $entryToEdit) { entry in
            EditEntryView(entry: entry) { updated in
                handleUpdate(updated)
            }
        }
        .task { await load() }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    // MARK: - Entry row (Tier 1 + Tier 2)

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
            .listRowBackground(Color.sunBackground)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
    }

    // MARK: - Edit update handler

    private func handleUpdate(_ updated: BestOfEntry) {
        if let idx = bestMomentsToday.firstIndex(where: { $0.id == updated.id }) {
            bestMomentsToday[idx] = updated
        } else if let idx = otherToday.firstIndex(where: { $0.id == updated.id }) {
            otherToday[idx] = updated
        } else if fallbackEntry?.id == updated.id {
            fallbackEntry = updated
        }
    }

    // MARK: - New Year's Day view

    private var newYearView: some View {
        let newYear = Calendar(identifier: .gregorian).component(.year, from: Date())
        return VStack(spacing: 16) {
            Text("🎆")
                .font(.system(size: 72))
            Text("Happy New Year")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Color.sunText)
            Text(String(newYear))
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.sunAccent)
            Text("See you on the other side")
                .font(.system(size: 14))
                .foregroundStyle(Color.sunSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
        .listRowBackground(Color.sunBackground)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
    }

    // MARK: - Date header

    private var dateHeader: some View {
        let contextLabel = hasToday
            ? "ON THIS DAY · \(todayCount)"
            : "JUST BECAUSE"

        return VStack(alignment: .leading, spacing: 6) {
            Text(Date().formatted(.dateTime.weekday(.wide)).uppercased())
                .font(.system(size: 11, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(Color.sunSecondary)

            Text(Date().formatted(.dateTime.month(.wide).day()))
                .font(.system(size: 32, weight: .bold))
                .fontDesign(.serif)
                .foregroundStyle(Color.sunText)

            Text(contextLabel)
                .font(.system(size: 10, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(hasToday ? Color.sunSecondary : Color.sunAccent)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(hasToday ? Color.sunSurface : Color.sunAccent.opacity(0.12))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(hasToday ? Color.white.opacity(0.1) : Color.sunAccent.opacity(0.35), lineWidth: 1))
                .padding(.top, 4)
        }
        .textCase(nil)
        .padding(.bottom, 12)
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 0, trailing: 16))
    }

    // MARK: - Fallback card

    private func fallbackCard(_ entry: BestOfEntry) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                CategoryChip(label: entry.category.rawValue, colorHex: entry.category.colorHex)
                Spacer()
                if !entry.isUnassigned {
                    Text(String(entry.year))
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(Color.sunSecondary)
                }
            }

            Text(entry.entry)
                .font(.system(size: 16, weight: .bold))
                .fontDesign(.serif)
                .foregroundStyle(Color.sunText)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !entry.notes.isEmpty {
                Text(entry.notes)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.sunSecondary)
                    .lineLimit(3)
            }
        }
        .padding(16)
        .background(Color.sunSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Skeleton

    private var skeletonView: some View {
        ScrollView {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    SkeletonEntryCard().frame(height: 12).opacity(0.5)
                    SkeletonEntryCard().frame(height: 28).opacity(0.7)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 24)

                VStack(spacing: 12) {
                    ForEach(0..<2, id: \.self) { _ in
                        SkeletonEntryCard().padding(.horizontal, 16)
                    }
                }
            }
        }
    }

    // MARK: - Load

    private func load(force: Bool = false) async {
        // Stale-while-revalidate: serve disk cache instantly, refresh in background
        if !force, let cached = NotionService.shared.bestOfDiskCache() {
            applyEntries(cached)
            isLoading = false
            do {
                let fresh = try await NotionService.shared.fetchBestOf(force: true)
                applyEntries(fresh)
            } catch is CancellationError {
            } catch let urlErr as URLError where urlErr.code == .cancelled {
            } catch { /* silently fail — user already sees cached data */ }
            return
        }
        // No disk cache (first-ever launch) or pull-to-refresh
        isLoading = true
        defer { isLoading = false }
        do {
            let all = try await NotionService.shared.fetchBestOf(force: force)
            applyEntries(all)
        } catch is CancellationError {
            return
        } catch let urlErr as URLError where urlErr.code == .cancelled {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func applyEntries(_ all: [BestOfEntry]) {
        let cal = Calendar(identifier: .gregorian)
        let now = Date()
        let todayMonth = cal.component(.month, from: now)
        let todayDay   = cal.component(.day, from: now)

        if todayMonth == 1 && todayDay == 1 {
            isNewYearsDay = true
            bestMomentsToday = []
            otherToday = []
            fallbackEntry = nil
            return
        }
        isNewYearsDay = false

        let todayEntries = all.filter { entry in
            !entry.isYearOnly &&
            cal.component(.month, from: entry.date) == todayMonth &&
            cal.component(.day, from: entry.date) == todayDay
        }

        bestMomentsToday = todayEntries
            .filter { $0.category == .bestMoments }
            .sorted { $0.year > $1.year }

        otherToday = todayEntries
            .filter { $0.category != .bestMoments && $0.category != .improvements }
            .sorted { $0.year > $1.year }

        // Tier 3 fallback: delegate to DailySetupService — same pick as the notification
        if bestMomentsToday.isEmpty && otherToday.isEmpty {
            fallbackEntry = DailySetupService.shared.selectEntry(for: now, from: all)
        } else {
            fallbackEntry = nil
        }
    }
}

