import SwiftUI
import UIKit

// 6 one-tap boops elevated from BoopView presets (user-selected 2026-04-19)
private let homeBoops: [String] = [
    "HUMMINGBIRD NEEDS A BRANCH 🌿",
    "Coming to rub your butt 🍑",
    "poop 💩",
    "🤘",
    "Miss you! 🦕",
    "Come cuddle me 🫶",
]

struct TodayView: View {
    // Memory = strict date-match (month/day hits); Nudge = strict Tier-3 year-only pick
    @State private var memoryEntries: [BestOfEntry] = []
    @State private var nudgeEntry: BestOfEntry? = nil
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isNewYearsDay = false

    // Boop tile state
    @State private var sendingBoop: String? = nil
    @State private var toastMessage: String? = nil
    @State private var toastTask: Task<Void, Never>? = nil
    @State private var showCustomBoop = false

    @State private var selectedEntry: BestOfEntry? = nil
    @State private var entryToEdit: BestOfEntry? = nil
    @Namespace private var cardNamespace

    private var hasMemory: Bool { !memoryEntries.isEmpty }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Color.sunBackground.ignoresSafeArea()

                VStack(spacing: 0) {
                    PageHeader(headerDateString) {
                        Button {
                            showCustomBoop = true
                        } label: {
                            Image(systemName: "square.and.pencil")
                                .font(.system(size: 16, weight: .semibold, design: .serif))
                                .foregroundStyle(Color.sunAccent)
                                .padding(8)
                                .background(Color.white.opacity(0.08))
                                .clipShape(Circle())
                        }
                    }

                    if isLoading {
                        skeletonView
                    } else {
                        List {
                            // NEW YEAR'S DAY banner (kept above boops so priority-1 Boop
                            // still works on Jan 1 — regression from Session 46 first pass)
                            if isNewYearsDay {
                                Section {
                                    newYearView
                                }
                            }

                            // BOOPS (one-tap) — always rendered, including NYD
                            Section {
                                boopGrid
                                    .listRowBackground(Color.sunBackground)
                                    .listRowSeparator(.hidden)
                                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 12, trailing: 16))
                            } header: {
                                sectionHeader("BOOPS", accent: true)
                            }

                            // MEMORY (date-matched only)
                            if hasMemory {
                                Section {
                                    ForEach(memoryEntries) { entry in entryRow(entry) }
                                } header: {
                                    sectionHeader("MEMORY · \(memoryEntries.count)", accent: false)
                                }
                            }

                            // NUDGE (Tier-3 year-only only)
                            if let entry = nudgeEntry {
                                Section {
                                    nudgeCard(entry)
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
                                } header: {
                                    sectionHeader("NUDGE", accent: true)
                                }
                            }

                            if !hasMemory && nudgeEntry == nil {
                                Section {
                                    Text("Nothing to show today — check back later!")
                                        .font(.system(.subheadline, design: .serif))
                                        .foregroundStyle(Color.sunSecondary)
                                        .padding(.vertical, 20)
                                        .frame(maxWidth: .infinity, alignment: .center)
                                        .listRowBackground(Color.sunBackground)
                                        .listRowSeparator(.hidden)
                                }
                            }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                        .refreshable { await load(force: true) }
                    }
                }

                // Transient toast
                if let msg = toastMessage {
                    Text(msg)
                        .font(.system(size: 13, weight: .semibold, design: .serif))
                        .foregroundStyle(Color.sunBackground)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.sunAccent)
                        .clipShape(Capsule())
                        .shadow(color: Color.sunAccent.opacity(0.45), radius: 10, x: 0, y: 4)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
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
        .sheet(item: $entryToEdit) { entry in
            EditEntryView(entry: entry) { updated in
                handleUpdate(updated)
            }
        }
        .sheet(isPresented: $showCustomBoop) {
            BoopView()
        }
        .task { await load() }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    // MARK: - Boop grid (3 columns × 2 rows)

    private var boopGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
            spacing: 10
        ) {
            ForEach(homeBoops, id: \.self) { preset in
                boopTile(preset)
            }
        }
    }

    private func boopTile(_ preset: String) -> some View {
        Button {
            Task { await sendOneTapBoop(preset) }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.sunSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )

                if sendingBoop == preset {
                    ProgressView()
                        .tint(Color.sunAccent)
                } else {
                    Text(preset)
                        .font(.system(size: 12, weight: .semibold, design: .serif))
                        .foregroundStyle(Color.sunText)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .minimumScaleFactor(0.7)
                        .padding(8)
                }
            }
            .frame(height: 80)
        }
        .buttonStyle(.plain)
        .disabled(sendingBoop != nil)
    }

    private func sendOneTapBoop(_ message: String) async {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        sendingBoop = message
        defer { sendingBoop = nil }
        // Toast is fire-and-forget — do NOT await it here, otherwise `sendingBoop`
        // stays locked for the 1.8s toast duration instead of just the send duration.
        do {
            try await BoopService.shared.send(message: message)
            showToast("Boop sent 💛")
        } catch {
            showToast("Send failed — try again")
        }
    }

    @MainActor
    private func showToast(_ message: String) {
        // Cancel any in-flight toast so the newer one wins — single shared
        // @State collides if two sends fire within 1.8s of each other.
        toastTask?.cancel()
        toastTask = Task { @MainActor in
            withAnimation(.easeOut(duration: 0.2)) { toastMessage = message }
            do {
                try await Task.sleep(nanoseconds: 1_800_000_000)
                withAnimation(.easeIn(duration: 0.25)) { toastMessage = nil }
            } catch {
                // Cancelled — a newer toast is taking over; leave the view state
                // alone so the new one's message isn't stomped.
            }
        }
    }

    // MARK: - Entry row

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

    private func handleUpdate(_ updated: BestOfEntry) {
        if let idx = memoryEntries.firstIndex(where: { $0.id == updated.id }) {
            memoryEntries[idx] = updated
        } else if nudgeEntry?.id == updated.id {
            nudgeEntry = updated
        }
    }

    // MARK: - New Year's Day view

    private var newYearView: some View {
        let newYear = Calendar(identifier: .gregorian).component(.year, from: Date())
        return VStack(spacing: 16) {
            Text("🎆")
                .font(.system(size: 72, design: .serif))
            Text("Happy New Year")
                .font(.system(size: 28, weight: .bold, design: .serif))
                .foregroundStyle(Color.sunText)
            Text(String(newYear))
                .font(.system(size: 20, weight: .semibold, design: .serif))
                .foregroundStyle(Color.sunAccent)
            Text("See you on the other side")
                .font(.system(size: 14, design: .serif))
                .foregroundStyle(Color.sunSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
        .listRowBackground(Color.sunBackground)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
    }

    // MARK: - Section headers

    private var headerDateString: String {
        Date().formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    private func sectionHeader(_ label: String, accent: Bool) -> some View {
        Text(label)
            .font(.system(size: 11, weight: .bold, design: .serif))
            .tracking(1.2)
            .foregroundStyle(accent ? Color.sunAccent : Color.sunSecondary)
            .textCase(nil)
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
    }

    // MARK: - Nudge card

    private func nudgeCard(_ entry: BestOfEntry) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                CategoryChip(label: entry.category.rawValue, colorHex: entry.category.colorHex)
                Spacer()
                if !entry.isUnassigned {
                    Text(String(entry.year))
                        .font(.system(size: 10, weight: .bold, design: .serif))
                        .tracking(0.8)
                        .foregroundStyle(Color.sunSecondary)
                }
            }

            Text(entry.entry)
                .font(.system(size: 16, weight: .bold, design: .serif))
                .fontDesign(.serif)
                .foregroundStyle(Color.sunText)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !entry.notes.isEmpty {
                Text(entry.notes)
                    .font(.system(size: 13, design: .serif))
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
        await DailySetupService.shared.runDailySetup()

        if !force, let cached = NotionService.shared.bestOfDiskCache() {
            applyEntries(cached)
            isLoading = false
            do {
                let fresh = try await NotionService.shared.fetchBestOf(force: true)
                applyEntries(fresh)
            } catch is CancellationError {
            } catch let urlErr as URLError where urlErr.code == .cancelled {
            } catch { }
            return
        }
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

    // STRICT split: Memory = date-matched, Nudge = Tier-3 year-only (no mixing)
    private func applyEntries(_ all: [BestOfEntry]) {
        let cal = Calendar(identifier: .gregorian)
        let now = Date()
        let todayMonth = cal.component(.month, from: now)
        let todayDay   = cal.component(.day, from: now)

        if todayMonth == 1 && todayDay == 1 {
            isNewYearsDay = true
            memoryEntries = []
            nudgeEntry = nil
            return
        }
        isNewYearsDay = false

        // Memory: every date-matched entry today, excluding improvements
        memoryEntries = all
            .filter { entry in
                !entry.isYearOnly &&
                entry.category != .improvements &&
                cal.component(.month, from: entry.date) == todayMonth &&
                cal.component(.day, from: entry.date) == todayDay
            }
            .sorted { lhs, rhs in
                // Best Moments first, then by year descending
                if lhs.category == .bestMoments && rhs.category != .bestMoments { return true }
                if lhs.category != .bestMoments && rhs.category == .bestMoments { return false }
                return lhs.year > rhs.year
            }

        // Nudge: strict Tier-3 year-only pick, excluding improvements
        let nudgePool = all.filter { $0.isYearOnly && $0.category != .improvements }
        nudgeEntry = DailySetupService.shared.selectEntry(for: now, from: nudgePool)
    }
}
