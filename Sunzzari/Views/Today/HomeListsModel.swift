import Foundation
import Combine
import SwiftUI

/// One row on a Home checklist. Deliberately carries nothing but an ID and a
/// name — Elisa's spec was "no data visible other than small checklist type things".
struct ChecklistItem: Identifiable, Equatable {
    let id: String          // real Notion page ID — required to check the row off
    let title: String
    /// Small coloured chips under the title: neighbourhood for a restaurant,
    /// streaming service for a show, Theaters/At Home for a movie, page sections
    /// for a recipe (which can be several).
    var chips: [String] = []
}

/// The four Home checklists plus the period summary.
///
/// Shortlist rule (Elisa, 2026-08-18): Home shows only rows flagged
/// `Thinking About`, never the full "haven't tried" set — that set is 176
/// restaurants and unreadable. Anything added from the app sets the flag.
@MainActor
final class HomeListsModel: ObservableObject {

    @Published var restaurants: [ChecklistItem] = []
    @Published var activities:  [ChecklistItem] = []
    @Published var movies:      [ChecklistItem] = []
    @Published var shows:       [ChecklistItem] = []
    @Published var recipes:     [ChecklistItem] = []
    /// Never rendered on Home — the travel card is an add button and a link, by
    /// Elisa's instruction. Kept so `.travel` can reuse the shared add sheet.
    @Published var travel:      [ChecklistItem] = []
    @Published var cycleEntries: [CycleEntry] = []

    /// Rows mid-write, so the circle can show progress and block a double tap.
    @Published var completing: Set<String> = []
    @Published var toast: String?

    // Full source lists, kept so a check-off stays consistent until the next fetch.
    private(set) var allRestaurants: [Restaurant] = []
    private(set) var allActivities:  [Activity] = []

    // MARK: - Load

    func load(force: Bool = false) async {
        let service = NotionService.shared
        async let r = try? service.fetchRestaurants(force: force)
        async let a = try? service.fetchActivities(force: force)
        async let w = try? service.fetchWatchlist(force: force)
        async let c = try? service.fetchCycleEntries(force: force)

        let (rest, acts, watch, cyc) = await (r, a, w, c)

        if let rest { allRestaurants = rest; restaurants = Self.shortlist(rest) }
        if let acts { allActivities = acts;  activities  = Self.shortlist(acts) }
        if let watch {
            movies = watch.filter { $0.kind == .movie && !$0.watched }
                          .map { ChecklistItem(id: $0.id, title: $0.title, chips: $0.locations) }
            shows  = watch.filter { $0.kind == .show && !$0.watched }
                          .map { ChecklistItem(id: $0.id, title: $0.title, chips: $0.locations) }
            recipes = watch.filter { $0.kind == .recipe && !$0.watched }
                           .map { ChecklistItem(id: $0.id, title: $0.title, chips: $0.locations) }
        }
        if let cyc { cycleEntries = cyc }
    }

    private static func shortlist(_ rs: [Restaurant]) -> [ChecklistItem] {
        rs.filter { $0.thinkingAbout && !$0.beenThere }
          .map { ChecklistItem(id: $0.id, title: $0.name,
                               chips: $0.neighborhood.isEmpty ? [] : [$0.neighborhood]) }
    }

    private static func shortlist(_ as_: [Activity]) -> [ChecklistItem] {
        as_.filter { $0.thinkingAbout && !$0.done }
           .map { ChecklistItem(id: $0.id, title: $0.name) }
    }

    // MARK: - Check off

    /// Optimistically drops the row, then writes. On failure the row comes back
    /// and the user is told — a silently swallowed write would look like it worked.
    func complete(_ item: ChecklistItem, in list: HomeList) async {
        guard !completing.contains(item.id) else { return }
        completing.insert(item.id)
        defer { completing.remove(item.id) }

        let snapshot = self[keyPath: list.itemsKey]
        guard let index = snapshot.firstIndex(where: { $0.id == item.id }) else { return }

        withAnimation(.easeOut(duration: 0.2)) {
            self[keyPath: list.itemsKey].removeAll { $0.id == item.id }
        }

        do {
            try await NotionService.shared.updatePageCheckboxes(pageID: item.id, values: list.completionProps)
            list.invalidateCache()
            applyLocalCompletion(item.id, in: list)
        } catch {
            withAnimation {
                self[keyPath: list.itemsKey].insert(item, at: min(index, self[keyPath: list.itemsKey].count))
            }
            toast = "Couldn't save — check connection"
        }
    }

    /// Keep the in-memory source lists honest so "browse all" counts don't drift
    /// until the next fetch.
    private func applyLocalCompletion(_ id: String, in list: HomeList) {
        switch list {
        case .restaurants:
            if let i = allRestaurants.firstIndex(where: { $0.id == id }) {
                allRestaurants[i].beenThere = true
                allRestaurants[i].thinkingAbout = false
            }
        case .activities:
            if let i = allActivities.firstIndex(where: { $0.id == id }) {
                allActivities[i].done = true
                allActivities[i].thinkingAbout = false
            }
        case .movies, .shows, .recipes, .travel:
            break
        }
    }

    // MARK: - Add

    func add(title: String, chips: [String], to list: HomeList) async {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let tags = chips.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let tag = tags.first
        do {
            let id: String
            switch list {
            case .restaurants:
                id = try await NotionService.shared.createRestaurantOnShortlist(name: name, neighborhood: tag)
            case .activities:
                id = try await NotionService.shared.createActivityOnShortlist(name: name)
            case .movies:
                id = try await NotionService.shared.createWatchlistItem(title: name, kind: .movie, locations: tags).id
            case .shows:
                id = try await NotionService.shared.createWatchlistItem(title: name, kind: .show, locations: tags).id
            case .travel:
                id = try await NotionService.shared.createTravelWishlistDestination(name: name, region: tag)
            case .recipes:
                id = try await NotionService.shared.createWatchlistItem(title: name, kind: .recipe, locations: tags).id
                // Mirror into Elisa's long-standing Home Cooking PAGE (not a database).
                // Best-effort: the card row is the source of truth for the short list,
                // so a failed page append must never lose what she just typed.
                if !tags.isEmpty {
                    do {
                        try await NotionService.shared.appendRecipeToHomeCooking(name: name, sections: tags)
                    } catch {
                        toast = "Added to the card, but not to your recipe page"
                    }
                }
            }
            withAnimation {
                self[keyPath: list.itemsKey].append(ChecklistItem(id: id, title: name, chips: tags))
            }
        } catch {
            toast = "Couldn't add — check connection"
        }
    }

}

// MARK: - List identity

enum HomeList: CaseIterable, Identifiable {
    var id: String { title }

    case restaurants, activities, movies, shows, recipes, travel

    var title: String {
        switch self {
        case .restaurants: return "RESTAURANTS TO TRY"
        case .activities:  return "ACTIVITIES TO DO"
        case .movies:      return "MOVIES TO WATCH"
        case .shows:       return "SHOWS TO WATCH"
        case .recipes:     return "HOME COOKING"
        case .travel:      return "PLACES TO GO"
        }
    }

    /// Half-width cards can't carry the long form.
    var shortTitle: String {
        switch self {
        case .restaurants: return "RESTAURANTS"
        case .activities:  return "ACTIVITIES"
        case .movies:      return "MOVIES"
        case .shows:       return "SHOWS"
        case .recipes:     return "HOME COOKING"
        case .travel:      return "TRAVEL"
        }
    }

    var addPrompt: String {
        switch self {
        case .restaurants: return "Restaurant name"
        case .activities:  return "Activity"
        case .movies:      return "Movie title"
        case .shows:       return "Show title"
        case .recipes:     return "Recipe"
        case .travel:      return "Destination"
        }
    }

    /// Options for the chip picker in the add sheet. Empty = free text (restaurants)
    /// or no chip at all (activities, recipes).
    var chipOptions: [String] {
        switch self {
        case .movies:  return WatchlistItem.Kind.movie.whereOptions
        case .shows:   return WatchlistItem.Kind.show.whereOptions
        case .recipes: return ["Healthy", "Not Healthy", "Special", "Asian"]
        case .travel:  return TravelWishlistItem.regionOptions
        default:       return []
        }
    }

    /// Label above the chip input; nil = this list has no chip.
    /// Only recipes allow several at once — a dish can be both Healthy and Asian.
    var allowsMultipleChips: Bool { self == .recipes }

    var chipLabel: String? {
        switch self {
        case .restaurants: return "Neighborhood"
        case .movies:      return "Where"
        case .shows:       return "Streaming on"
        case .recipes:     return "Section"
        case .travel:      return "Region"
        case .activities:  return nil
        }
    }

    var emptyText: String {
        switch self {
        case .restaurants: return "Nothing on the list yet"
        case .activities:  return "Nothing on the list yet"
        case .movies:      return "No movies queued"
        case .shows:       return "No shows queued"
        case .recipes:     return "Nothing to cook yet"
        case .travel:      return "Nowhere on the list yet"
        }
    }

    /// Checkboxes flipped when a row is checked off, per the STRUCTURE.md
    /// conventions for each DB.
    var completionProps: [String: Bool] {
        switch self {
        case .restaurants: return ["Been There?": true, "Thinking About": false]
        case .activities:  return ["Done?": true, "Thinking About": false]
        case .movies, .shows, .recipes: return ["Watched": true]
        // Travel has no "Thinking About" shortlist flag: the whole wishlist is the
        // shortlist, so checking a destination off only records that we went.
        case .travel:      return ["Been There": true]
        }
    }

    var itemsKey: ReferenceWritableKeyPath<HomeListsModel, [ChecklistItem]> {
        switch self {
        case .restaurants: return \HomeListsModel.restaurants
        case .activities:  return \HomeListsModel.activities
        case .movies:      return \HomeListsModel.movies
        case .shows:       return \HomeListsModel.shows
        case .recipes:     return \HomeListsModel.recipes
        case .travel:      return \HomeListsModel.travel
        }
    }

    /// Lists with a back catalogue worth its own screen.
    var supportsBrowse: Bool {
        self == .restaurants || self == .activities || self == .travel
    }

    func invalidateCache() {
        switch self {
        case .restaurants: NotionService.shared.invalidateRestaurants()
        case .activities:  NotionService.shared.invalidateActivities()
        case .movies, .shows, .recipes: NotionService.shared.invalidateWatchlist()
        case .travel:      NotionService.shared.invalidateTravelWishlist()
        }
    }
}
