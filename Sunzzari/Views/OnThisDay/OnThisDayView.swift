import SwiftUI

struct OnThisDayView: View {
    @State private var todaysMemories: [Memory] = []
    @State private var isLoading = true
    @State private var showAddMemory = false
    @State private var memoryToEdit: Memory? = nil
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.sunBackground.ignoresSafeArea()

                if isLoading {
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(0..<4, id: \.self) { _ in
                                SkeletonEntryCard().padding(.horizontal, 16)
                            }
                        }
                        .padding(.vertical, 16)
                    }
                } else if todaysMemories.isEmpty {
                    EmptyStateView(
                        systemImage: "calendar.badge.clock",
                        title: "Nothing on this day yet",
                        subtitle: "Add a memory for today and it will appear here each year."
                    )
                } else {
                    List {
                        Section {
                            ForEach(todaysMemories.sorted { $0.date > $1.date }) { memory in
                                MemoryCardView(memory: memory)
                                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                        Button {
                                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                            memoryToEdit = memory
                                        } label: {
                                            Label("Edit", systemImage: "pencil")
                                        }
                                        .tint(.orange)
                                    }
                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                        Button(role: .destructive) {
                                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                            withAnimation { todaysMemories.removeAll { $0.id == memory.id } }
                                            Task { try? await NotionService.shared.archivePage(id: memory.id) }
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                    .listRowBackground(Color.sunBackground)
                                    .listRowSeparator(.hidden)
                                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
                            }
                        } header: {
                            dateHeader
                                .textCase(nil)
                                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .refreshable { await load(force: true) }
                }

                addButton
            }
            .navigationTitle("On This Day")
            .navigationBarTitleDisplayMode(.large)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .sheet(isPresented: $showAddMemory, onDismiss: { Task { await load() } }) {
            AddMemoryView()
        }
        .sheet(item: $memoryToEdit) { memory in
            EditMemoryView(memory: memory) { updated in
                if let idx = todaysMemories.firstIndex(where: { $0.id == updated.id }) {
                    todaysMemories[idx] = updated
                }
            }
        }
        .task { await load() }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private var dateHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(Date().formatted(.dateTime.weekday(.wide)))
                    .font(.caption)
                    .foregroundStyle(Color.sunSecondary)
                Text(Date().formatted(.dateTime.month(.wide).day()))
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Color.sunAccent)
            }
            Spacer()
            Text("\(todaysMemories.count) \(todaysMemories.count == 1 ? "MEMORY" : "MEMORIES")")
                .font(.system(size: 10, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(Color.sunSecondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Color.sunSurface)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.1), lineWidth: 1))
        }
        .padding(.vertical, 8)
    }

    private var addButton: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Button { showAddMemory = true } label: {
                    Image(systemName: "plus")
                        .font(.title2.weight(.semibold))
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

    private func load(force: Bool = false) async {
        // Stale-while-revalidate: serve disk cache instantly, refresh in background
        if !force, let cached = NotionService.shared.memoriesDiskCache() {
            todaysMemories = cached.filter { $0.occursOn(monthDay: Date()) }
            isLoading = false
            do {
                let fresh = try await NotionService.shared.fetchMemories(force: true)
                todaysMemories = fresh.filter { $0.occursOn(monthDay: Date()) }
            } catch is CancellationError {
            } catch let urlErr as URLError where urlErr.code == .cancelled {
            } catch { /* silently fail — user already sees cached data */ }
            return
        }
        // No disk cache (first-ever launch) or pull-to-refresh
        isLoading = true
        defer { isLoading = false }
        do {
            let all = try await NotionService.shared.fetchMemories(force: force)
            todaysMemories = all.filter { $0.occursOn(monthDay: Date()) }
        } catch is CancellationError {
            return
        } catch let urlErr as URLError where urlErr.code == .cancelled {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
