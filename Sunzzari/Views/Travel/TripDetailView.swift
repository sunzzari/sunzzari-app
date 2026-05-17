import SwiftUI
import MapKit
import CoreLocation

enum TripViewMode: String, CaseIterable, Identifiable {
    case mapList, day
    var id: String { rawValue }
    var label: String {
        switch self {
        case .mapList: return "Map"
        case .day:     return "Day"
        }
    }
}

struct TripDetailView: View {
    let trip: Trip

    @Environment(\.horizontalSizeClass) private var sizeClass

    // Data
    @State private var items: [TripItem] = []
    @State private var isLoading = true
    @State private var isOffline = false

    // View mode
    @State private var viewMode: TripViewMode = .mapList

    // Map
    @State private var selectedID: String?
    @State private var bridge = TripMapBridge()
    @State private var isFullscreen = false

    // Filters
    @State private var activeStatuses: Set<TripItem.ItemStatus> = []
    @State private var activeTypes: Set<TripItem.ItemType> = []
    @State private var activeLegs: Set<String> = []
    @State private var searchQuery = ""
    @State private var selectedDate: String?
    @State private var sortMode: TripSortMode = .type
    @State private var nearMeActive = false
    @State private var filterReservationOnly = false

    // Location
    @State private var userLocation: CLLocation?

    // Detail sheet
    @State private var detailItem: TripItem?

    // AI assistant
    @State private var showAssistant = false

    private var dayBundles: [DayBundle] {
        DayGrouper.group(items: items, trip: trip)
    }

    // MARK: - Computed

    private var filteredItems: [TripItem] {
        items.filter { item in
            let statusOK = activeStatuses.isEmpty || item.status.map { activeStatuses.contains($0) } ?? false
            let typeOK = activeTypes.isEmpty || item.type.map { activeTypes.contains($0) } ?? false
            let legOK = activeLegs.isEmpty || activeLegs.contains(item.legCity)
            let searchOK = searchQuery.isEmpty ||
                item.name.localizedCaseInsensitiveContains(searchQuery) ||
                item.venue.localizedCaseInsensitiveContains(searchQuery)
            let dateOK = selectedDate == nil || item.displayDate == selectedDate
            let nearMeOK: Bool = {
                guard nearMeActive, let loc = userLocation, let lat = item.latitude, let lon = item.longitude else {
                    return !nearMeActive
                }
                return loc.distance(from: CLLocation(latitude: lat, longitude: lon)) <= 5000
            }()
            let reservOK = !filterReservationOnly || item.reservationRequired
            return statusOK && typeOK && legOK && searchOK && dateOK && nearMeOK && reservOK
        }
    }

    private var sortedItems: [TripItem] {
        let list = filteredItems
        if nearMeActive, let loc = userLocation {
            return list.sorted { a, b in
                let distA = distanceTo(a, from: loc)
                let distB = distanceTo(b, from: loc)
                return distA < distB
            }
        }
        switch sortMode {
        case .type:
            return list.sorted { ($0.type?.sortOrder ?? 99) < ($1.type?.sortOrder ?? 99) }
        case .date:
            return list.sorted { ($0.displayDate ?? "9999") < ($1.displayDate ?? "9999") }
        case .priority:
            return list.sorted { ($0.priority?.sortOrder ?? 99) < ($1.priority?.sortOrder ?? 99) }
        }
    }

    private var annotations: [TripItemAnnotation] {
        filteredItems.compactMap { item in
            guard let lat = item.latitude, let lon = item.longitude else { return nil }
            return TripItemAnnotation(
                item: item,
                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon)
            )
        }
    }

    private var filterKey: String {
        "\(activeStatuses.map(\.rawValue).sorted())-\(activeTypes.map(\.rawValue).sorted())-\(activeLegs.sorted())-\(searchQuery)-\(selectedDate ?? "")-\(nearMeActive)"
    }

    private var uniqueDates: [String] {
        Array(Set(items.compactMap(\.displayDate))).sorted()
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.sunBackground.ignoresSafeArea()

            if isLoading && items.isEmpty {
                ProgressView()
                    .tint(Color.sunAccent)
            } else {
                mainContent
            }
        }
        .navigationTitle(trip.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(Color.sunSurface, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("View", selection: $viewMode) {
                    ForEach(TripViewMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 240)
            }
            ToolbarItem(placement: .topBarTrailing) {
                if viewMode == .mapList {
                    TripSortPicker(sortMode: $sortMode, nearMeActive: nearMeActive)
                }
            }
        }
        .sheet(item: $detailItem) { item in
            ItemDetailSheet(item: item, userLocation: userLocation)
        }
        .sheet(isPresented: $showAssistant) {
            TripAssistantSheet(
                items: items,
                trip: trip,
                userLocation: userLocation,
                onSelectItem: { item in selectItem(item) }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .task {
            await loadItems()
        }
        .onChange(of: nearMeActive) { _, active in
            if active {
                requestUserLocation()
                // Pan to user so the dot lands in frame; auto-fit on the next
                // updateUIView (driven by filterKey change) will then include
                // the user via fitIncludesUser=nearMeActive.
                if let coord = LocationService.shared.lastKnownCoordinate {
                    DispatchQueue.main.async {
                        bridge.panTo(coord, zoom: 5000)
                    }
                }
            }
        }
        .onChange(of: searchQuery)    { _, _ in selectedID = nil }
        .onChange(of: activeStatuses) { _, _ in selectedID = nil }
        .onChange(of: activeTypes)    { _, _ in selectedID = nil }
        .onChange(of: activeLegs)     { _, _ in selectedID = nil }
        .onChange(of: selectedDate)   { _, _ in selectedID = nil }
        .animation(.easeInOut(duration: 0.2), value: viewMode)
    }

    @ViewBuilder
    private var mainContent: some View {
        switch viewMode {
        case .mapList:
            mapListContent
                .transition(.opacity)
        case .day:
            DayDetailView(
                trip: trip,
                days: dayBundles,
                selectedID: $selectedID,
                userLocation: userLocation,
                onSelect: selectItem
            )
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private var mapListContent: some View {
        if sizeClass == .regular {
            // iPad: sidebar + map
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    filterBar
                    if !uniqueDates.isEmpty {
                        DayTimelineView(dates: uniqueDates, selectedDate: $selectedDate)
                    }
                    TripSidebarView(
                        items: sortedItems,
                        selectedID: selectedID,
                        userLocation: userLocation,
                        onSelect: selectItem
                    )
                }
                .frame(width: 300)

                mapLayer
            }
        } else {
            // iPhone: fullscreen map + bottom sheet
            ZStack {
                mapLayer

                if !isFullscreen {
                    VStack(spacing: 0) {
                        filterBar
                        if !uniqueDates.isEmpty {
                            DayTimelineView(dates: uniqueDates, selectedDate: $selectedDate)
                        }
                        Spacer()
                    }

                    TripBottomSheetView(
                        items: sortedItems,
                        selectedID: $selectedID,
                        userLocation: userLocation,
                        onSelect: selectItem
                    )
                }
            }
        }
    }

    private var filterBar: some View {
        VStack(spacing: 0) {
            if isOffline {
                HStack(spacing: 8) {
                    Image(systemName: "wifi.slash")
                    Text("Viewing cached data")
                }
                .font(.system(.caption, design: .serif))
                .foregroundStyle(Color.sunBackground)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .background(Color.sunAccent)
            }

            TripFilterBar(
                items: items,
                displayCount: sortedItems.count,
                activeStatuses: $activeStatuses,
                activeTypes: $activeTypes,
                activeLegs: $activeLegs,
                filterReservationOnly: $filterReservationOnly,
                searchQuery: $searchQuery,
                nearMeActive: $nearMeActive
            )
        }
    }

    private var mapLayer: some View {
        ZStack {
            TripMKMap(
                annotations: annotations,
                filterKey: filterKey,
                selectedID: $selectedID,
                bridge: bridge,
                fitIncludesUser: nearMeActive,
                onOpenDetail: { item in detailItem = item }
            )
            .ignoresSafeArea(edges: .bottom)

            // Map controls - top right. Sparkles is last so it clears
            // the filter bar + date timeline that overlay the top ~90pt.
            VStack(spacing: 8) {
                mapButton(icon: isFullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right") {
                    withAnimation { isFullscreen.toggle() }
                }

                mapButton(icon: "arrow.up.left.and.down.right.magnifyingglass") {
                    bridge.fitAll(includeUser: nearMeActive)
                }

                mapButton(icon: "location.fill") {
                    bridge.centerOnUser()
                }

                Button {
                    showAssistant = true
                } label: {
                    Image(systemName: "sparkles")
                        .font(.system(.caption, design: .serif))
                        .foregroundStyle(Color.sunAccent)
                        .frame(width: 36, height: 36)
                        .background(Color.sunSurface.opacity(0.9))
                        .clipShape(Circle())
                        .shadow(color: Color.sunAccent.opacity(0.3), radius: 4)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .padding(12)
        }
    }

    private func mapButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(.caption, design: .serif))
                .foregroundStyle(Color.sunText)
                .frame(width: 36, height: 36)
                .background(Color.sunSurface.opacity(0.9))
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.2), radius: 2)
        }
    }

    // MARK: - Actions

    private func selectItem(_ item: TripItem) {
        if let lat = item.latitude, let lon = item.longitude {
            DispatchQueue.main.async {
                self.bridge.panTo(CLLocationCoordinate2D(latitude: lat, longitude: lon))
            }
        }
        if selectedID == item.id {
            detailItem = item   // second tap -> open detail
        } else {
            selectedID = item.id // first tap -> select + pan only
        }
    }

    private func requestUserLocation() {
        if let coord = LocationService.shared.lastKnownCoordinate {
            userLocation = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        }
    }

    // MARK: - Data

    private func loadItems(force: Bool = false) async {
        if items.isEmpty { isLoading = true }
        do {
            var fetched = try await TravelService.shared.fetchTripItems(tripId: trip.id, force: force)
            // Phase 1: show items with cached coordinates immediately
            fetched = TravelService.shared.applyCachedCoordinates(fetched)
            items = fetched
            isLoading = false
            isOffline = TravelService.shared.isOffline
            // Phase 2: geocode remaining items in background, biased by trip location
            // so "Paris"/"Rome" resolve to the right country.
            let geocoded = await TravelService.shared.geocodeItems(fetched, tripLocation: trip.location)
            items = geocoded
        } catch is CancellationError {
            return
        } catch let urlErr as URLError where urlErr.code == .cancelled {
            return
        } catch {
            if let cached = TravelService.shared.itemsDiskCache(tripId: trip.id) {
                items = cached
                isOffline = true
            }
        }
        isLoading = false
    }

    private func distanceTo(_ item: TripItem, from location: CLLocation) -> Double {
        guard let lat = item.latitude, let lon = item.longitude else { return .greatestFiniteMagnitude }
        return location.distance(from: CLLocation(latitude: lat, longitude: lon))
    }
}

// Make TripItem work with .sheet(item:)
extension TripItem: Hashable {
    static func == (lhs: TripItem, rhs: TripItem) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
