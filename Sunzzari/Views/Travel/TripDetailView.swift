import SwiftUI
import MapKit
import CoreLocation

struct TripDetailView: View {
    let trip: Trip

    @Environment(\.horizontalSizeClass) private var sizeClass

    // Data
    @State private var items: [TripItem] = []
    @State private var isLoading = true
    @State private var isOffline = false
    @State private var isRefreshing = false
    @State private var loadErrorMessage: String?

    // Itinerary viewer
    @State private var showItinerary = false

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
    // Pins sharing one coordinate: zooming cannot split them, so pick from a list.
    @State private var clusterItems: ClusterSelection?

    // AI assistant
    @State private var showAssistant = false
    @State private var assistantQuery = ""
    @State private var assistantResponse: TripAssistantResponse?
    @State private var assistantError: String?
    @State private var assistantSelectedItemID: String?

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
                // No fix yet: don't filter — the old code returned false here,
                // which blanked the ENTIRE map whenever Near Me was toggled
                // before a location arrived. A banner explains the wait instead.
                guard nearMeActive, let loc = userLocation else { return true }
                guard let lat = item.latitude, let lon = item.longitude else { return false }
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

    private var highlightedItemIds: Set<String> {
        Set(assistantResponse?.matchedItemIds ?? [])
    }

    private var itineraryURLString: String {
        if let u = trip.itineraryURL, !u.isEmpty { return u }
        let slug = trip.id.replacingOccurrences(of: "-", with: "")
        return "https://elisa-travel-map.vercel.app/\(slug)/itinerary"
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.sunBackground.ignoresSafeArea()

            if isLoading && items.isEmpty {
                ProgressView()
                    .tint(Color.sunAccent)
            } else if items.isEmpty, let message = loadErrorMessage {
                loadErrorState(message)
            } else {
                mainContent
            }
        }
        .navigationTitle(trip.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(Color.sunSurface, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                TripSortPicker(sortMode: $sortMode, nearMeActive: nearMeActive)
            }
            ToolbarItem(placement: .topBarTrailing) {
                // Manual refresh: edits made in Notion mid-planning shouldn't
                // have to wait out the 5-minute cache TTL.
                Button {
                    guard !isRefreshing else { return }
                    Task {
                        isRefreshing = true
                        await loadItems(force: true)
                        isRefreshing = false
                    }
                } label: {
                    if isRefreshing {
                        ProgressView()
                            .tint(Color.sunAccent)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .foregroundStyle(Color.sunAccent)
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showItinerary = true
                } label: {
                    Image(systemName: "list.bullet.clipboard")
                        .foregroundStyle(Color.sunAccent)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { TripTodayView(trip: trip) } label: {
                    Image(systemName: "calendar.day.timeline.left")
                        .foregroundStyle(Color.sunAccent)
                }
            }
        }
        .sheet(item: $detailItem) { item in
            ItemDetailSheet(item: item, userLocation: userLocation)
        }
        .sheet(item: $clusterItems) { selection in
            ClusterPickerSheet(items: selection.items) { item in
                clusterItems = nil
                detailItem = item
            }
        }
        .sheet(isPresented: $showAssistant) {
            TripAssistantSheet(
                items: items,
                trip: trip,
                userLocation: userLocation,
                onSelectItem: { item in
                    // Clear date filter so this item's annotation is on the map
                    if selectedDate != nil && item.displayDate != selectedDate {
                        selectedDate = nil
                    }
                    selectItem(item)
                },
                query: $assistantQuery,
                response: $assistantResponse,
                errorMessage: $assistantError,
                selectedItemID: $assistantSelectedItemID
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showItinerary) {
            ItineraryWebView(urlString: itineraryURLString)
        }
        .onChange(of: assistantResponse) { _, newResponse in
            guard let newResponse, !newResponse.matchedItemIds.isEmpty else { return }
            // Usurp the day filter so all matched items appear on the map
            selectedDate = nil
            let matchedIds = Set(newResponse.matchedItemIds)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                bridge.fitToIDs(matchedIds, in: items)
            }
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
        .onReceive(NotificationCenter.default.publisher(for: .ownLocationDidUpdate)) { _ in
            // A one-shot fix requested by Near Me (or any background update)
            // just landed — adopt it and frame the user if Near Me is waiting.
            guard let coord = LocationService.shared.lastKnownCoordinate else { return }
            let hadLocation = userLocation != nil
            userLocation = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
            if nearMeActive && !hadLocation {
                bridge.panTo(coord, zoom: 5000)
            }
        }
        .onChange(of: searchQuery)    { _, _ in selectedID = nil }
        .onChange(of: activeStatuses) { _, _ in selectedID = nil }
        .onChange(of: activeTypes)    { _, _ in selectedID = nil }
        .onChange(of: activeLegs)     { _, _ in selectedID = nil }
        .onChange(of: selectedDate)   { _, _ in selectedID = nil }
    }

    @ViewBuilder
    private var mainContent: some View {
        mapListContent
    }

    @ViewBuilder
    private var mapListContent: some View {
        if sizeClass == .regular {
            // iPad: sidebar + map. Fullscreen hides the sidebar — previously
            // the button toggled state this branch never read (dead tap target).
            HStack(spacing: 0) {
                if !isFullscreen {
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
                }

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

                    if !showAssistant {
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

            if nearMeActive && userLocation == nil {
                HStack(spacing: 8) {
                    Image(systemName: "location.slash")
                    Text("Waiting for location — showing all items")
                }
                .font(.system(.caption, design: .serif))
                .foregroundStyle(Color.sunSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .background(Color.sunSurface)
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
                onOpenDetail: { item in detailItem = item },
                onOpenCluster: { clusterItems = ClusterSelection(items: $0) },
                highlightedItemIds: highlightedItemIds
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
            let coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            DispatchQueue.main.async {
                // 600m zoom breaks city-level clusters so the individual pin
                // is visible when selectPin fires 0.7s later.
                self.bridge.panTo(coord, zoom: 600)
                self.bridge.selectPin(id: item.id)
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
        } else {
            // Nothing cached (fresh install, or location never authorized):
            // prompt + one-shot fix; .ownLocationDidUpdate delivers the result.
            LocationService.shared.requestLocationForNearMe()
        }
    }

    private func loadErrorState(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(.title2, design: .serif))
                .foregroundStyle(Color.sunAccent)
            Text("Couldn't load trip items")
                .font(.system(.headline, design: .serif))
                .foregroundStyle(Color.sunText)
            Text(message)
                .font(.system(.caption, design: .serif))
                .foregroundStyle(Color.sunSecondary)
                .multilineTextAlignment(.center)
            Button("Retry") {
                Task { await loadItems(force: true) }
            }
            .font(.system(.subheadline, design: .serif))
            .foregroundStyle(Color.sunAccent)
        }
        .padding(24)
    }

    // MARK: - Data

    private func loadItems(force: Bool = false) async {
        if items.isEmpty { isLoading = true }
        do {
            let result = try await TravelService.shared.fetchTripItems(tripId: trip.id, force: force)
            // Phase 1: show items with cached coordinates immediately
            let fetched = TravelService.shared.applyCachedCoordinates(result.items)
            items = fetched
            isLoading = false
            isOffline = result.isOffline
            loadErrorMessage = nil
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
            // No cache: name the failure instead of showing an empty map.
            if items.isEmpty { loadErrorMessage = error.localizedDescription }
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
