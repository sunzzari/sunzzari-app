import SwiftUI

struct MyActivitiesView: View {
    @State private var activities: [Activity] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    // Filters
    @State private var activeOnly = false
    @State private var seasonalOnly = false
    @State private var homeOnly = false
    @State private var dateSpecificOnly = false

    private var hasActiveFilters: Bool {
        activeOnly || seasonalOnly || homeOnly || dateSpecificOnly
    }

    private var filtered: [Activity] {
        activities.filter { a in
            (!activeOnly || a.active) &&
            (!seasonalOnly || a.seasonal) &&
            (!homeOnly || a.home) &&
            (!dateSpecificOnly || a.dateSpecific)
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
                    activityList
                }
            }
        }
        .navigationTitle("My Activities")
        .navigationBarTitleDisplayMode(.large)
            .toolbarColorScheme(.dark, for: .navigationBar)
        .task { await load() }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private var activityList: some View {
        List {
            if filtered.isEmpty {
                Text("No activities match your filters")
                    .font(.subheadline)
                    .foregroundStyle(Color.sunSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 40)
                    .listRowBackground(Color.sunBackground)
                    .listRowSeparator(.hidden)
            } else {
                ForEach(filtered) { a in
                    ActivityCardView(activity: a)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                withAnimation { activities.removeAll { $0.id == a.id } }
                                Task { try? await NotionService.shared.archivePage(id: a.id) }
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
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip("Active", isOn: $activeOnly)
                filterChip("Seasonal", isOn: $seasonalOnly)
                filterChip("Home", isOn: $homeOnly)
                filterChip("Date-Specific", isOn: $dateSpecificOnly)

                if hasActiveFilters {
                    Button {
                        activeOnly = false; seasonalOnly = false
                        homeOnly = false; dateSpecificOnly = false
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

    private func filterChip(_ label: String, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .bold))
                .tracking(0.8)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(isOn.wrappedValue ? Color.sunAccent.opacity(0.12) : Color.clear)
                .foregroundStyle(isOn.wrappedValue ? Color.sunAccent : Color.sunSecondary)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(isOn.wrappedValue ? Color.sunAccent.opacity(1) : Color.white.opacity(0.2), lineWidth: 1))
                .shadow(color: isOn.wrappedValue ? Color.sunAccent.opacity(0.4) : .clear, radius: 6, y: 0)
        }
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
        isLoading = true
        defer { isLoading = false }
        do {
            activities = try await NotionService.shared.fetchActivities(force: force)
        } catch is CancellationError {
            return
        } catch let urlErr as URLError where urlErr.code == .cancelled {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
