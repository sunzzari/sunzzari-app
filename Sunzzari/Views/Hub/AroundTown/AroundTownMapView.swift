import SwiftUI
import MapKit

// The map itself is the travel map's `TripMKMap`. There is no Around Town map
// class any more, and that is the point: a numbered bubble here behaves the way
// it behaves on a trip because it is the same code, not because someone
// remembered to copy the fix across. `AroundTownItem.asTripItem` is the whole
// adapter. This file owns the Around Town-specific parts -- the filter bar, the
// preference legend and the intent toggles. It places nothing: every pin, and
// every chain branch, arrives already placed from the travel map server
// (`AroundTownService`), the same answer the website draws.

// MARK: - AroundTownMapView

struct AroundTownMapView: View {
    @Binding var items: [AroundTownItem]
    /// Called after a place's location is saved, so the caller can pull the
    /// server's fresh answer and the new pin appears.
    let onLocationSaved: () async -> Void

    /// Opens pre-filtered. My Restaurants' map button lands here on
    /// `.restaurant` now that the separate restaurant map is gone.
    init(
        items: Binding<[AroundTownItem]>,
        initialKind: AroundTownItem.Kind? = nil,
        onLocationSaved: @escaping () async -> Void = {}
    ) {
        self._items = items
        self._filterKind = State(initialValue: initialKind)
        self.onLocationSaved = onLocationSaved
    }

    @State private var selectedID: String?
    // ONE sheet, selected by case. Two separate .sheet modifiers on the same
    // view silently conflict -- the cluster sheet never presented until these
    // were merged.
    private enum ActiveSheet: Identifiable {
        case detail(String)
        case cluster([AroundTownItem])
        case unmapped
        case findIt(String)
        case edit(Restaurant)
        case addRestaurant
        case addActivity

        var id: String {
            switch self {
            case .detail(let itemID): return "detail-\(itemID)"
            case .cluster(let members): return "cluster-" + members.map(\.id).joined(separator: "-")
            case .unmapped: return "unmapped"
            case .findIt(let itemID): return "find-\(itemID)"
            case .edit(let restaurant): return "edit-\(restaurant.id)"
            case .addRestaurant: return "add-restaurant"
            case .addActivity: return "add-activity"
            }
        }
    }

    @State private var activeSheet: ActiveSheet?
    @State private var bridge = TripMapBridge()
    /// The place whose edit screen is being opened, while Notion is read.
    @State private var openingEditID: String?
    @State private var editError: String?

    @State private var filterRegion: AroundTownItem.Region? = nil
    @State private var filterKind: AroundTownItem.Kind? = nil
    @State private var wantToTryOnly = false
    /// "Haven't Tried": hides the places we have been to. One on/off chip, the
    /// same as the website's, not a switch with an "Around Town" half.
    @State private var hideBeenThere = false

    private var hasActiveFilters: Bool {
        filterRegion != nil || filterKind != nil || wantToTryOnly || hideBeenThere
    }

    private var filtered: [AroundTownItem] {
        items.filter { item in
            let regionOK = filterRegion == nil || item.region == filterRegion
            let kindOK   = filterKind == nil || item.kind == filterKind
            let triedOK  = !hideBeenThere || !item.done
            let wantOK   = !wantToTryOnly || item.thinkingAbout
            return regionOK && kindOK && triedOK && wantOK
        }
    }

    /// One pin per place, plus one per chain branch.
    private var annotations: [TripItemAnnotation] {
        filtered.flatMap(\.annotations)
    }

    private var mappedCount: Int {
        filtered.reduce(0) { $0 + ($1.coordinate == nil ? 0 : 1) }
    }

    /// The places with no saved location. Counted in the control bar and
    /// reachable from it -- a row she cannot open is a row she cannot use. Each
    /// one opens to a "Find it" that gives it a pin.
    private var unmappedPlaces: [AroundTownItem] {
        filtered.filter { $0.coordinate == nil }
    }

    /// The ONE area a fit may span. Elisa, 2026-09-14: *"id never want to fit all
    /// between sf and la. id fit all within one area but not all areas."*
    ///
    /// Her explicit LA / SF Bay choice wins. With no choice made it is whichever
    /// area holds more of the places currently on screen, which is deterministic
    /// and needs no location permission -- Locate Me is the control for "take me
    /// to where I actually am".
    private var fitRegion: AroundTownItem.Region {
        if let filterRegion { return filterRegion }
        var la = 0, sf = 0
        for item in filtered where item.coordinate != nil {
            switch item.region {
            case .la: la += 1
            case .sfBay: sf += 1
            case nil: break
            }
        }
        return sf > la ? .sfBay : .la
    }

    /// Pins inside `fitRegion`'s FIT area, which is tighter than the area the
    /// region accepts pins from - LA here means LA County, not San Diego and
    /// Orange County too. Pins outside it stay on the map and stay tappable;
    /// they are simply never allowed to stretch the frame. An empty scope makes
    /// `TripMKMap.fitToIDs` fall back to fitting everything, so a filter that
    /// leaves nothing in LA proper still frames something.
    private var fitScopeIDs: Set<String> {
        // Which frame a pin belongs to is the server's call (`fitArea`), the
        // same rule the website uses, so the two never frame LA differently.
        // A chain's branches follow the same rule as any pin.
        let region = fitRegion
        var ids = Set<String>()
        for item in filtered where item.coordinate != nil {
            if item.fitArea == region { ids.insert(item.id) }
            for (index, branch) in item.branches.enumerated() where branch.fitArea == region {
                ids.insert(AroundTownItem.branchID(item.id, index))
            }
        }
        return ids
    }

    /// Rare path: a tap on a cluster or a callout. A linear scan is fine here.
    /// A branch pin carries its place's id plus a suffix; both resolve here.
    private func item(withID id: String) -> AroundTownItem? {
        let placeID = AroundTownItem.placeID(of: id)
        return items.first { $0.id == placeID }
    }

    /// Hot path: the map calls `styleFor` for EVERY annotation on EVERY update,
    /// so the lookup behind it cannot be a scan. At 410 places a scan-per-pin is
    /// ~168k string compares per refresh, on the main thread, while she pans.
    /// Built once per body evaluation and captured by the closure.
    private var pinStyleByID: [String: MapPinStyle] {
        Dictionary(items.map { ($0.id, $0.pinStyle) }, uniquingKeysWith: { first, _ in first })
    }

    private var filterKey: String {
        let kindStr = filterKind.map { $0 == .restaurant ? "rest" : "act" } ?? "all"
        // fitRegion is in the key: when the majority area flips as places
        // load, the map should re-frame on it rather than keep an old frame.
        return "\(filterRegion?.label ?? "all")|\(kindStr)|\(hideBeenThere ? "nottried" : "all")|\(wantToTryOnly)|fit:\(fitRegion.label)"
    }

    var body: some View {
        let pinStyles = pinStyleByID
        return ZStack {
            // The travel map, with Around Town data and Around Town pin colours.
            TripMKMap(
                annotations: annotations,
                filterKey: filterKey,
                selectedID: $selectedID,
                bridge: bridge,
                onOpenDetail: { activeSheet = .detail(AroundTownItem.placeID(of: $0.id)) },
                onOpenCluster: { trip in
                    // Two branches of one chain in the same bubble are one place.
                    var seen = Set<String>()
                    let members = trip.compactMap { item(withID: $0.id) }.filter { seen.insert($0.id).inserted }
                    if !members.isEmpty { activeSheet = .cluster(members) }
                },
                styleFor: { trip in
                    pinStyles[AroundTownItem.placeID(of: trip.id)]
                        ?? MapPinStyle(color: Color(hex: AroundTownItem.notRatedHex), glyph: "mappin")
                },
                initialRegion: MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: 34.05, longitude: -118.24),
                    latitudinalMeters: 60_000, longitudinalMeters: 60_000
                ),
                fitScopeIDs: fitScopeIDs
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                controlBar
                Spacer()
            }

            VStack {
                Spacer()
                HStack(alignment: .bottom, spacing: 0) {
                    kindLegend
                        .padding(.leading, 16)
                    Spacer()
                    VStack(spacing: 10) {
                        fitAllButton
                        locateMeButton
                    }
                    .padding(.trailing, 16)
                }
                .padding(.bottom, 32)
            }
        }
        .navigationTitle("Around Town")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .detail(let id):
                if let idx = items.firstIndex(where: { $0.id == id }) {
                    calloutSheet(binding: $items[idx])
                        .presentationDetents([.fraction(0.55), .large])
                        .presentationDragIndicator(.visible)
                }
            case .cluster(let members):
                placeListSheet(title: "\(members.count) places here", members: members)
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
            case .unmapped:
                placeListSheet(
                    title: "\(unmappedPlaces.count) with no map location",
                    members: unmappedPlaces,
                    note: "No pin yet. Open one and tap Find it to give it a pin."
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            case .findIt(let id):
                if let place = item(withID: id) {
                    PlaceFinderSheet(item: place, onSaved: onLocationSaved)
                        .presentationDetents([.large])
                        .presentationDragIndicator(.visible)
                }
            // The Restaurants list's own edit screen, not a second one. The
            // map reloads when it closes, so the sheet shows what was saved.
            case .edit(let restaurant):
                RestaurantEditView(restaurant: restaurant) { _ in }
                    .onDisappear { Task { await onLocationSaved() } }
            // The app's existing add forms, not new ones. They save the place
            // and its pin; the map reloads when the form closes.
            case .addRestaurant:
                AddRestaurantView()
                    .onDisappear { Task { await onLocationSaved() } }
            case .addActivity:
                AddActivityView()
                    .onDisappear { Task { await onLocationSaved() } }
            }
        }
        // A failed "Edit" belongs to the sheet it happened on.
        .onChange(of: activeSheet?.id) { editError = nil }
        .toolbar {
            // Same job as "+ Add place" on the website's Around Town.
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { activeSheet = .addRestaurant } label: { Label("Restaurant", systemImage: "fork.knife") }
                    Button { activeSheet = .addActivity } label: { Label("Activity", systemImage: "figure.walk") }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.sunAccent)
                }
                .accessibilityLabel("Add a place")
            }
        }
    }

    // MARK: - Controls

    private var controlBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Text("\(mappedCount) on the map")
                    .font(.system(size: 11, design: .serif))
                    .foregroundStyle(Color.white.opacity(0.45))
                if filtered.count > mappedCount {
                    // These rows have no saved location. Tapping opens them:
                    // unmapped is fine, invisible is not.
                    Button {
                        activeSheet = .unmapped
                    } label: {
                        HStack(spacing: 3) {
                            Text("· \(filtered.count - mappedCount) with no map location")
                            Image(systemName: "chevron.right")
                                .font(.system(size: 8, weight: .bold, design: .serif))
                        }
                        .font(.system(size: 11, design: .serif))
                        .foregroundStyle(Color.white.opacity(0.55))
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.horizontal, 18)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    filterChip(label: "LA", isActive: filterRegion == .la) {
                        filterRegion = filterRegion == .la ? nil : .la
                    }
                    filterChip(label: "SF Bay", isActive: filterRegion == .sfBay) {
                        filterRegion = filterRegion == .sfBay ? nil : .sfBay
                    }

                    Rectangle()
                        .fill(Color.white.opacity(0.15))
                        .frame(width: 1, height: 16)

                    filterChip(label: "Restaurants", icon: "fork.knife", isActive: filterKind == .restaurant) {
                        filterKind = filterKind == .restaurant ? nil : .restaurant
                    }
                    filterChip(label: "Activities", icon: "figure.walk", isActive: filterKind == .activity) {
                        filterKind = filterKind == .activity ? nil : .activity
                    }

                    Rectangle()
                        .fill(Color.white.opacity(0.15))
                        .frame(width: 1, height: 16)

                    filterChip(label: "Want to Try", icon: "bookmark", isActive: wantToTryOnly) {
                        wantToTryOnly.toggle()
                    }
                    filterChip(label: "Haven't Tried", icon: "eye.slash", isActive: hideBeenThere) {
                        hideBeenThere.toggle()
                    }

                    if hasActiveFilters {
                        Button {
                            filterRegion = nil
                            filterKind = nil
                            wantToTryOnly = false
                            hideBeenThere = false
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9, weight: .bold, design: .serif))
                                Text("Clear")
                                    .font(.system(size: 12, design: .serif))
                            }
                            .foregroundStyle(Color.white.opacity(0.5))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.07))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .background(Color.black.opacity(0.45))
    }

    private func filterChip(
        label: String,
        icon: String? = nil,
        isActive: Bool,
        onTap: @escaping () -> Void
    ) -> some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 9, weight: .semibold, design: .serif))
                }
                Text(label)
                    .font(.system(size: 12, weight: .medium, design: .serif))
            }
            .foregroundStyle(isActive ? Color.sunBackground : Color.white.opacity(0.75))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isActive ? Color.sunAccent : Color.white.opacity(0.08))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(
                isActive ? Color.sunAccent : Color.white.opacity(0.2),
                lineWidth: 1
            ))
            .shadow(color: isActive ? Color.sunAccent.opacity(0.45) : .clear, radius: 6)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Kind legend (bottom-left)

    private var kindLegend: some View {
        // The old legend claimed blue = Restaurant, but restaurant pins are
        // coloured by Preference, so four of the five colours on screen were
        // unexplained. This states what the colours actually mean.
        VStack(alignment: .leading, spacing: 5) {
            legendRow(color: Color(hex: "#54A0FF"), label: "Top Choice")
            legendRow(color: Color(hex: "#70C17C"), label: "Great")
            legendRow(color: Color(hex: "#FBBF24"), label: "Good")
            legendRow(color: Color(hex: "#FF6B6B"), label: "Bad")
            legendRow(color: Color(hex: AroundTownItem.notRatedHex), label: "Not rated")
            legendRow(color: Color(hex: AroundTownItem.activityHex), label: "Activity")
            legendRow(color: Color.gray, label: "Been there")
            // Credit the pin sources, as the OpenStreetMap licence asks.
            Text("Pins: OpenStreetMap, US Census")
                .font(.system(size: 8, design: .serif))
                .foregroundStyle(Color.white.opacity(0.45))
                .padding(.top, 2)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .background(Color(hex: "#030712").opacity(0.75))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.1), lineWidth: 1))
    }

    private func legendRow(color: Color, label: String) -> some View {
        HStack(spacing: 7) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
            Text(label)
                .font(.system(size: 11, weight: .medium, design: .serif))
                .foregroundStyle(Color.white.opacity(0.75))
        }
    }

    // MARK: - Locate Me

    private var locateMeButton: some View {
        Button {
            bridge.centerOnUser()
        } label: {
            Image(systemName: "location.fill")
                .font(.system(size: 16, design: .serif))
                .foregroundStyle(Color.sunAccent)
                .padding(13)
                .background(Color.sunSurface)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.5), radius: 8, y: 3)
        }
    }

    /// Back to every pin in ONE area. Never LA and the Bay at once -- that
    /// frames 400 miles of California and turns every pin into a speck.
    private var fitAllButton: some View {
        Button {
            selectedID = nil
            let ids = fitScopeIDs
            guard !ids.isEmpty else { return }
            // Branch pins included, so a chain's branches are framed as well as drawn.
            bridge.fitToIDs(ids, in: filtered.flatMap(\.annotations).map(\.item))
        } label: {
            Image(systemName: "scope")
                .font(.system(size: 16, design: .serif))
                .foregroundStyle(Color.sunAccent)
                .padding(13)
                .background(Color.sunSurface)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.5), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Place list (cluster members, and places with no pin)

    /// One list, two jobs: the members of a numbered bubble that no amount of
    /// zooming will separate, and the places that have no saved location yet.
    /// A row for a place that HAS a pin points the map at it, the way tapping a
    /// trip row does; a row with no pin opens its description.
    @ViewBuilder
    private func placeListSheet(
        title: String,
        members: [AroundTownItem],
        note: String? = nil
    ) -> some View {
        ZStack {
            Color.sunBackground.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: 18, weight: .bold, design: .serif))
                    .foregroundStyle(Color.sunText)
                    .padding(.horizontal, 20)
                    .padding(.top, 22)
                    .padding(.bottom, note == nil ? 12 : 4)

                if let note {
                    Text(note)
                        .font(.system(size: 12, design: .serif))
                        .foregroundStyle(Color.sunSecondary)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)
                }

                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(members) { member in
                            Button {
                                if let coord = member.coordinate {
                                    // Same behaviour as a tapped trip row: point
                                    // the map at it rather than covering the map
                                    // with a sheet.
                                    activeSheet = nil
                                    selectedID = member.id
                                    bridge.panTo(coord)
                                    bridge.selectPin(id: member.id)
                                } else {
                                    activeSheet = .detail(member.id)
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: member.glyph)
                                        .font(.system(size: 13, design: .serif))
                                        .foregroundStyle(member.done
                                                         ? Color.gray
                                                         : Color(hex: member.markerColorHex))
                                        .frame(width: 22)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(member.name)
                                            .font(.system(size: 15, weight: .medium, design: .serif))
                                            .foregroundStyle(Color.sunText)
                                        Text(member.calloutSubtitle)
                                            .font(.system(size: 12, design: .serif))
                                            .foregroundStyle(Color.sunSecondary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    Image(systemName: member.coordinate == nil
                                          ? "chevron.right"
                                          : "mappin.and.ellipse")
                                        .font(.system(size: 11, design: .serif))
                                        .foregroundStyle(Color.sunSecondary.opacity(0.5))
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            Divider().background(Color.white.opacity(0.07))
                        }
                    }
                }
            }
        }
    }

    // MARK: - Detail sheet

    @ViewBuilder
    private func calloutSheet(binding: Binding<AroundTownItem>) -> some View {
        let item = binding.wrappedValue
        ZStack {
            Color.sunBackground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 6) {
                        kindBadge(item.kind)
                        if let region = item.region {
                            Text(region.label)
                                .font(.system(size: 11, weight: .medium, design: .serif))
                                .foregroundStyle(Color.sunSecondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.white.opacity(0.06))
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
                        }
                        if let pref = item.preferenceLabel, !pref.isEmpty {
                            Text(pref)
                                .font(.system(size: 11, weight: .medium, design: .serif))
                                .foregroundStyle(Color(hex: item.markerColorHex))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color(hex: item.markerColorHex).opacity(0.12))
                                .clipShape(Capsule())
                        }
                        Spacer()
                        // Same job as "Edit" on the website's Around Town.
                        // Activities have no edit screen in this app.
                        if item.kind == .restaurant {
                            editButton(for: item)
                        }
                    }

                    if let editError {
                        Text(editError)
                            .font(.system(size: 12, design: .serif))
                            .foregroundStyle(.red)
                    }

                    Text(item.name)
                        .font(.system(size: 20, weight: .bold, design: .serif))
                        .foregroundStyle(Color.sunText)

                    if !item.subtitle.isEmpty {
                        Text(item.subtitle)
                            .font(.system(.subheadline, design: .serif))
                            .foregroundStyle(Color.sunSecondary)
                    }

                    if !item.goodFor.isEmpty {
                        Text(item.goodFor.joined(separator: " · "))
                            .font(.system(size: 13, design: .serif))
                            .foregroundStyle(Color.sunSecondary.opacity(0.85))
                    }

                    if !item.topDishes.isEmpty {
                        detailBlock(title: "Top dishes", body: item.topDishes)
                    }
                    if !item.comments.isEmpty {
                        detailBlock(title: "Notes", body: item.comments)
                    }

                    if item.coordinate == nil {
                        // No pin yet. "Find it" looks the place up (free, on the
                        // server) and saves its address and pin, the same flow
                        // the website has.
                        Button {
                            activeSheet = .findIt(item.id)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "mappin.and.ellipse")
                                Text("Find it")
                            }
                            .font(.system(size: 13, weight: .semibold, design: .serif))
                            .foregroundStyle(Color.sunBackground)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(Color.sunAccent)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)

                        Button {
                            let query = [item.name, item.locationText]
                                .filter { !$0.isEmpty }
                                .joined(separator: " ")
                            let encoded = query.addingPercentEncoding(
                                withAllowedCharacters: .urlQueryAllowed
                            ) ?? ""
                            if let url = URL(string: "http://maps.apple.com/?q=\(encoded)") {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "magnifyingglass")
                                Text("Look up in Maps")
                            }
                            .font(.system(size: 13, weight: .medium, design: .serif))
                            .foregroundStyle(Color.sunAccent)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(Color.sunAccent.opacity(0.1))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Color.sunAccent.opacity(0.3), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }

                    Divider()
                        .background(Color.white.opacity(0.1))

                    HStack(spacing: 12) {
                        intentButton(
                            label: "Want to Try",
                            icon: item.thinkingAbout ? "bookmark.fill" : "bookmark",
                            isActive: item.thinkingAbout,
                            color: Color.sunAccent
                        ) {
                            let newVal = !binding.wrappedValue.thinkingAbout
                            binding.wrappedValue.thinkingAbout = newVal
                            let id = item.id
                            Task { try? await NotionService.shared.updatePageCheckbox(
                                pageID: id, property: "Thinking About", value: newVal
                            )}
                        }

                        intentButton(
                            label: "Been There",
                            icon: item.done ? "checkmark.circle.fill" : "checkmark.circle",
                            isActive: item.done,
                            color: Color(hex: "#70C17C")
                        ) {
                            let newDone = !binding.wrappedValue.done
                            binding.wrappedValue.done = newDone
                            if newDone { binding.wrappedValue.thinkingAbout = false }
                            let id = item.id
                            let doneProperty = item.kind == .restaurant ? "Been There?" : "Done?"
                            Task {
                                try? await NotionService.shared.updatePageCheckbox(
                                    pageID: id, property: doneProperty, value: newDone
                                )
                                if newDone {
                                    try? await NotionService.shared.updatePageCheckbox(
                                        pageID: id, property: "Thinking About", value: false
                                    )
                                }
                            }
                        }
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// Opens the Restaurants list's edit screen for a place on the map. The
    /// form saves every field, so it starts from Notion's row as it is right
    /// now, not from the map's copy, which can be minutes old.
    private func editButton(for item: AroundTownItem) -> some View {
        Button {
            guard openingEditID == nil else { return }
            openingEditID = item.id
            editError = nil
            Task {
                defer { openingEditID = nil }
                do {
                    activeSheet = .edit(try await NotionService.shared.fetchRestaurant(id: item.id))
                } catch {
                    editError = "Could not open the editor. Check the connection and try again."
                }
            }
        } label: {
            HStack(spacing: 4) {
                if openingEditID == item.id {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(Color.sunAccent)
                } else {
                    Image(systemName: "pencil")
                        .font(.system(size: 11, weight: .semibold, design: .serif))
                }
                Text("Edit")
                    .font(.system(size: 12, weight: .semibold, design: .serif))
            }
            .foregroundStyle(Color.sunAccent)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.sunAccent.opacity(0.1))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color.sunAccent.opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Edit \(item.name)")
    }

    private func detailBlock(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold, design: .serif))
                .foregroundStyle(Color.sunSecondary.opacity(0.6))
            Text(body)
                .font(.system(size: 14, design: .serif))
                .foregroundStyle(Color.sunText)
        }
    }

    private func kindBadge(_ kind: AroundTownItem.Kind) -> some View {
        let (label, color): (String, Color) = kind == .restaurant
            ? ("Restaurant", Color(hex: "#54A0FF"))
            : ("Activity", Color(hex: "#A78BFA"))
        return Text(label)
            .font(.system(size: 11, weight: .medium, design: .serif))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(color.opacity(0.35), lineWidth: 1))
    }

    private func intentButton(
        label: String,
        icon: String,
        isActive: Bool,
        color: Color,
        onTap: @escaping () -> Void
    ) -> some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium, design: .serif))
                Text(label)
                    .font(.system(size: 14, weight: .medium, design: .serif))
            }
            .foregroundStyle(isActive ? Color.sunBackground : color)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(isActive ? color : color.opacity(0.1))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(isActive ? color : color.opacity(0.3), lineWidth: 1))
            .shadow(color: isActive ? color.opacity(0.4) : .clear, radius: 5)
        }
        .buttonStyle(.plain)
    }
}
