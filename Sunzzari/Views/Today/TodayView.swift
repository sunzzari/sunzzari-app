import SwiftUI

struct TodayView: View {
    @State private var bestMomentsToday: [BestOfEntry] = []
    @State private var otherToday: [BestOfEntry] = []
    @State private var fallbackEntry: BestOfEntry? = nil
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isNewYearsDay = false

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
                                    BestOfEntryCard(entry: entry)
                                        .listRowBackground(Color.sunBackground)
                                        .listRowSeparator(.hidden)
                                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                                }
                                // Tier 2: Other categories for today
                                ForEach(otherToday) { entry in
                                    BestOfEntryCard(entry: entry)
                                        .listRowBackground(Color.sunBackground)
                                        .listRowSeparator(.hidden)
                                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                                }
                            } else if let entry = fallbackEntry {
                                // Tier 3: Random unassigned fallback
                                fallbackCard(entry)
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
            .toolbarBackground(Color.sunBackground, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .task { await load() }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
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
                .foregroundStyle(Color.sunText)

            Text(contextLabel)
                .font(.system(size: 10, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(Color.sunSecondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Color.sunSurface)
                .clipShape(RoundedRectangle(cornerRadius: 5))
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
        isLoading = true
        defer { isLoading = false }
        do {
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

            let all = try await NotionService.shared.fetchBestOf(force: force)

            // Filter entries that match today's month+day, exclude year-only entries (YYYY-01-01)
            let todayEntries = all.filter { entry in
                !entry.isYearOnly &&
                cal.component(.month, from: entry.date) == todayMonth &&
                cal.component(.day, from: entry.date) == todayDay
            }

            // Tier 1: Best Moments first (primary category), newest year first
            bestMomentsToday = todayEntries
                .filter { $0.category == .bestMoments }
                .sorted { $0.year > $1.year }

            // Tier 2: All other categories (except Improvements), newest year first
            otherToday = todayEntries
                .filter { $0.category != .bestMoments && $0.category != .improvements }
                .sorted { $0.year > $1.year }

            // Tier 3: Nothing for today — stable fallback via UserDefaults (same entry all day)
            let todayKey = "sunzzari_fallback_\(DateFormatter.sunYYYYMMdd.string(from: now))"
            if bestMomentsToday.isEmpty && otherToday.isEmpty {
                let unassigned = all.filter { $0.isYearOnly && $0.category != .improvements }
                if let savedID = UserDefaults.standard.string(forKey: todayKey),
                   let saved = unassigned.first(where: { $0.id == savedID }) {
                    fallbackEntry = saved
                } else {
                    fallbackEntry = unassigned.randomElement()
                    if let chosen = fallbackEntry {
                        UserDefaults.standard.set(chosen.id, forKey: todayKey)
                    }
                }
            } else {
                fallbackEntry = nil
            }
        } catch is CancellationError {
            return
        } catch let urlErr as URLError where urlErr.code == .cancelled {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - DateFormatter helpers
private extension DateFormatter {
    static let sunYYYYMMdd: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}
