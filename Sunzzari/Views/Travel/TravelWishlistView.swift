import SwiftUI
import Combine
import UIKit

/// The full travel wishlist: every place we want to go, grouped by region, with
/// the months that are actually good to be there.
///
/// This is the "view travel wishlist" half of the Home travel card. The Home
/// card shows nothing, so this screen is the only place the list is rendered —
/// which is why it loads its own data rather than sharing HomeListsModel.
struct TravelWishlistView: View {
    @StateObject private var model = TravelWishlistModel()
    @State private var showAdd = false

    var body: some View {
        ZStack {
            Color.sunBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                SerifNavHeader("Wishlist") {
                    Button { showAdd = true } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.sunAccent)
                            .frame(width: 30, height: 30)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }

                content
            }

            if let msg = model.toast {
                VStack {
                    Text(msg)
                        .font(.system(size: 13, weight: .semibold, design: .serif))
                        .foregroundStyle(Color.sunBackground)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.sunAccent)
                        .clipShape(Capsule())
                        .padding(.top, 8)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showAdd) {
            HomeChecklistAddView(list: .travel) { name, chips in
                await model.add(name: name, region: chips.first)
            }
        }
        .task { await model.load() }
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoading && model.items.isEmpty {
            Spacer()
            ProgressView().tint(Color.sunAccent)
            Spacer()
        } else if let error = model.loadError, model.items.isEmpty {
            // Never a blank screen on failure: name what broke and offer a retry.
            Spacer()
            VStack(spacing: 12) {
                Text("Couldn't load the wishlist")
                    .font(.system(size: 16, weight: .bold, design: .serif))
                    .foregroundStyle(Color.sunText)
                Text(error)
                    .font(.system(size: 13, design: .serif))
                    .foregroundStyle(Color.sunSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Button("Retry") { Task { await model.load(force: true) } }
                    .font(.system(size: 15, weight: .semibold, design: .serif))
                    .foregroundStyle(Color.sunAccent)
            }
            Spacer()
        } else {
            List {
                ForEach(model.regionSections, id: \.name) { section in
                    Section {
                        ForEach(section.items) { item in row(item) }
                    } header: {
                        header("\(section.name.uppercased()) · \(section.items.count)")
                    }
                }

                if !model.visited.isEmpty {
                    Section {
                        ForEach(model.visited) { item in row(item) }
                    } header: {
                        header("BEEN THERE · \(model.visited.count)")
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .refreshable { await model.load(force: true) }
        }
    }

    private func header(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold, design: .serif))
            .tracking(1.2)
            .foregroundStyle(Color.sunSecondary)
            .textCase(nil)
            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 4, trailing: 16))
    }

    private func row(_ item: TravelWishlistItem) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            Task { await model.toggleVisited(item) }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    Circle()
                        .strokeBorder(Color.sunSecondary.opacity(0.55), lineWidth: 1.4)
                        .frame(width: 17, height: 17)
                    if item.beenThere {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color.sunAccent)
                    }
                    if model.updating.contains(item.id) {
                        ProgressView().controlSize(.mini).tint(Color.sunAccent)
                    }
                }
                .padding(.top, 2)

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .font(.system(size: 15, design: .serif))
                        .foregroundStyle(item.beenThere ? Color.sunSecondary : Color.sunText)
                        .strikethrough(item.beenThere, color: Color.sunSecondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    let best = item.bestMonthsSummary
                    if !best.isEmpty || !item.notes.isEmpty {
                        HStack(spacing: 5) {
                            if !best.isEmpty {
                                ChecklistChip(text: "Best: \(best)")
                            }
                            if !item.notes.isEmpty {
                                ChecklistChip(text: item.notes)
                            }
                        }
                    }

                    if !item.timingNotes.isEmpty {
                        Text(item.timingNotes)
                            .font(.system(size: 11, design: .serif))
                            .foregroundStyle(Color.sunSecondary.opacity(0.8))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .disabled(model.updating.contains(item.id))
        .listRowBackground(Color.sunBackground)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
    }
}

// MARK: - Model

@MainActor
final class TravelWishlistModel: ObservableObject {
    @Published var items: [TravelWishlistItem] = []
    @Published var updating: Set<String> = []
    @Published var isLoading = false
    @Published var loadError: String?
    @Published var toast: String?

    struct RegionSection { let name: String; let items: [TravelWishlistItem] }

    /// Regions in the order they are defined, so the list does not reshuffle
    /// between loads. Anything with an unrecognised region falls into "Other".
    var regionSections: [RegionSection] {
        let pending = items.filter { !$0.beenThere }
        var sections = TravelWishlistItem.regionOptions.compactMap { region -> RegionSection? in
            let matching = pending.filter { $0.region == region }
            return matching.isEmpty ? nil : RegionSection(name: region, items: matching)
        }
        let known = Set(TravelWishlistItem.regionOptions)
        let other = pending.filter { !known.contains($0.region) }
        if !other.isEmpty { sections.append(RegionSection(name: "Other", items: other)) }
        return sections
    }

    var visited: [TravelWishlistItem] { items.filter(\.beenThere) }

    func load(force: Bool = false) async {
        isLoading = true
        defer { isLoading = false }
        do {
            items = try await NotionService.shared.fetchTravelWishlist(force: force)
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    /// Optimistic, with a rollback. A silently swallowed failure would look
    /// exactly like a success and quietly lose the change.
    func toggleVisited(_ item: TravelWishlistItem) async {
        guard !updating.contains(item.id),
              let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        updating.insert(item.id)
        defer { updating.remove(item.id) }

        let newValue = !item.beenThere
        withAnimation(.easeOut(duration: 0.2)) { items[index].beenThere = newValue }

        do {
            try await NotionService.shared.updatePageCheckboxes(
                pageID: item.id, values: ["Been There": newValue])
            NotionService.shared.invalidateTravelWishlist()
        } catch {
            withAnimation { items[index].beenThere = !newValue }
            showToast("Couldn't save — check connection")
        }
    }

    func add(name: String, region: String?) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            let id = try await NotionService.shared.createTravelWishlistDestination(
                name: trimmed, region: region)
            withAnimation {
                items.append(TravelWishlistItem(
                    id: id, name: trimmed, region: region ?? "", season: [],
                    beenThere: false, notes: "", timingNotes: "",
                    monthRatings: Array(repeating: nil, count: 12)))
            }
        } catch {
            showToast("Couldn't add — check connection")
        }
    }

    private func showToast(_ msg: String) {
        withAnimation { toast = msg }
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            withAnimation { toast = nil }
        }
    }
}
