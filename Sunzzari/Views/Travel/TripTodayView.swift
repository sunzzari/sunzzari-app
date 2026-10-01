import SwiftUI
import CoreLocation
import MapKit

/// The during-the-trip screen: one day at a time, opening on today.
///
/// This exists because the map and the trip list answer "what is this trip",
/// and on a Thursday morning in Park City the question is "what is happening
/// today". Everything here is ordered for a ten-second skim, and everything it
/// needs is on disk, so it works with no signal.
/// What the day strip is filtering to.
///
/// `.all` is the default. The map is the screen; a day is something she opts
/// into. Elisa, 2026-09-08: "open the app to a very functional map 100% of the
/// time... and then ALSO to toggle today view which filters the map".
enum DaySelection: Equatable {
    case all
    case day(Int)
}

struct TripTodayView: View {
    let trip: Trip

    @State private var items: [TripItem] = []
    @State private var plans: [TripDayPlanner.DayPlan] = []
    @State private var selection: DaySelection = .all
    @State private var isLoading = true
    @State private var isRefreshing = false
    @State private var isOffline = false
    @State private var loadErrorMessage: String?
    @State private var detailItem: TripItem?
    @State private var userLocation: CLLocation?
    @State private var activeTypes: Set<TripItem.ItemType> = []
    /// "Confirmed only" on the map. Elisa, 2026-09-06: "let me toggle
    /// 'confirmed only' so i can see everything thats close to me."
    @State private var confirmedOnly = false

    // Ported from TripDetailView before it was retired: this is the one map
    // now, so everything that lived only there has to live here.
    @State private var searchQuery = ""
    @State private var activeLegs: Set<String> = []
    @State private var nearMe = false
    @State private var isFullscreen = false
    @State private var mapSelectedID: String?
    @State private var mapBridge = TripMapBridge()
    @State private var showQuickAdd = false
    @State private var clusterItems: ClusterSelection?

    // Ask-about-this-trip. Reuses TripAssistantSheet rather than building a
    // second one: it already answers "where should I eat near here" against the
    // trip's own items, which is exactly what she asked for on this screen.
    @State private var showAssistant = false
    @State private var assistantQuery = ""
    @State private var assistantResponse: TripAssistantResponse?
    @State private var assistantError: String?
    @State private var assistantSelectedItemID: String?

    /// The day she has opened, or nil while the strip is on All.
    private var day: TripDayPlanner.DayPlan? {
        guard let index = selectedDayIndex, plans.indices.contains(index) else { return nil }
        return plans[index]
    }

    private var selectedDayIndex: Int? {
        if case .day(let index) = selection { return index }
        return nil
    }

    /// Every item still in play, dated or not. This is the map's pool on All,
    /// and it is what makes a trip with nothing scheduled show its places
    /// instead of an empty screen.
    private var liveItems: [TripItem] {
        items.filter { $0.status != nil && $0.status != .cancelled }
    }

    /// Quick add has to attach to a day. On All that is the day the trip would
    /// have opened on, so the + never goes dead just because no day is picked.
    private var quickAddDay: TripDayPlanner.DayPlan? {
        if let day { return day }
        let index = TripDayPlanner.openingIndex(in: plans, timeZoneID: trip.timeZoneID)
        return plans.indices.contains(index) ? plans[index] : nil
    }

    /// Resolved in the TRIP's timezone, never the phone's.
    private var tripToday: String { TripDayPlanner.today(in: trip.timeZoneID) }
    private var isToday: Bool { day?.dateString == tripToday }

    private var legs: [String] {
        Array(Set(items.map(\.legCity).filter { !$0.isEmpty })).sorted()
    }

    /// A tap on an event points at the map. Elisa, 2026-09-08: "instead of the
    /// event details coming up when you click on an event, i want it to be
    /// highlighted on the map. if i want to see the details i can click see
    /// more details off of the tile on the map."
    ///
    /// The details are still one tap away, on the (i) in the pin's callout.
    /// An item with no coordinate has no pin to point at, so for that one case
    /// the sheet is still the only way in - otherwise the tap would do nothing.
    private func select(_ item: TripItem) {
        guard let lat = item.latitude, let lon = item.longitude else {
            detailItem = item
            return
        }
        mapSelectedID = item.id
        mapBridge.panTo(CLLocationCoordinate2D(latitude: lat, longitude: lon))
        mapBridge.selectPin(id: item.id)
        // Pointing at a pin she cannot see is not pointing at anything: in day
        // mode the map sits below the confirmed list.
        withAnimation(.easeOut(duration: 0.25)) { scrollToMap?() }
    }

    /// Set by the content ScrollViewReader. Optional so `select` stays callable
    /// from anywhere without threading a proxy through every row.
    @State private var scrollToMap: (() -> Void)?

    /// One predicate for the map and the lists, so a toggle can never filter
    /// one and not the other.
    private func matches(_ item: TripItem) -> Bool {
        let q = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        if !activeTypes.isEmpty, !(item.type.map { activeTypes.contains($0) } ?? false) { return false }
        if !activeLegs.isEmpty, !activeLegs.contains(item.legCity) { return false }
        if confirmedOnly, item.status != .confirmed { return false }
        if !q.isEmpty,
           !item.name.lowercased().contains(q),
           !item.venue.lowercased().contains(q),
           !item.notes.lowercased().contains(q) { return false }
        if nearMe {
            guard let loc = userLocation, let lat = item.latitude, let lon = item.longitude,
                  loc.distance(from: CLLocation(latitude: lat, longitude: lon)) <= 5000 else { return false }
        }
        return true
    }


    // MARK: - Body

    var body: some View {
        ZStack {
            Color.sunBackground.ignoresSafeArea()

            if isLoading && items.isEmpty {
                ProgressView().tint(Color.sunAccent)
            } else if items.isEmpty {
                emptyState
            } else {
                content
            }
        }
        .navigationTitle(trip.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(Color.sunSurface, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAssistant = true } label: {
                    Image(systemName: "sparkles").foregroundStyle(Color.sunAccent)
                }
                .disabled(items.isEmpty)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showQuickAdd = true } label: {
                    Image(systemName: "plus").foregroundStyle(Color.sunAccent)
                }
                .disabled(quickAddDay == nil)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    guard !isRefreshing else { return }
                    Task {
                        isRefreshing = true
                        await load(force: true)
                        isRefreshing = false
                    }
                } label: {
                    if isRefreshing {
                        ProgressView().tint(Color.sunAccent)
                    } else {
                        Image(systemName: "arrow.clockwise").foregroundStyle(Color.sunAccent)
                    }
                }
            }
        }
        .sheet(item: $detailItem) { ItemDetailSheet(item: $0, userLocation: userLocation) }
        .sheet(isPresented: $showAssistant) {
            TripAssistantSheet(
                items: items,
                trip: trip,
                userLocation: userLocation,
                onSelectItem: { item in
                    showAssistant = false
                    detailItem = item
                },
                query: $assistantQuery,
                response: $assistantResponse,
                errorMessage: $assistantError,
                selectedItemID: $assistantSelectedItemID
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $clusterItems) { selection in
            ClusterPickerSheet(items: selection.items) { item in
                clusterItems = nil
                detailItem = item
            }
        }
        .sheet(isPresented: $showQuickAdd) {
            if let day = quickAddDay {
                QuickAddItemSheet(
                    trip: trip,
                    dayString: day.dateString,
                    legCity: day.legCity,
                    onCreated: { _ in
                        // Re-read from Notion rather than splicing the returned
                        // item in: the day it lands on depends on the planner,
                        // not on what the form thinks it sent.
                        Task { await load(force: true) }
                    }
                )
            }
        }
        .task { await load() }
        .onAppear {
            // Remember this screen so the next launch comes straight back here.
            TravelResume.remember(tripID: trip.id)
            userLocation = LocationService.shared.lastKnownCoordinate.map {
                CLLocation(latitude: $0.latitude, longitude: $0.longitude)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .ownLocationDidUpdate)) { _ in
            guard let coord = LocationService.shared.lastKnownCoordinate else { return }
            userLocation = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            filterBar
            if !plans.isEmpty { dayStrip }

            ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if isOffline { offlineBanner }

                    if let day {
                        dayHeader(day)
                        if isToday, let next = upNext(in: day) { upNextCard(next) }
                        if !day.needsBooking.isEmpty { needsBookingCard(day.needsBooking) }
                        if let hotel = day.hotel { sleepingCard(hotel) }

                        // ABOVE the map: only what is settled. Elisa, 2026-09-06:
                        // "only list confirmed things above the map."
                        confirmedSection(day)

                        mapSection(
                            pool: day.scheduled.map(\.item) + day.options,
                            scopeKey: day.dateString,
                            title: "Around you"
                        )
                        .id(Self.mapAnchor)

                        // BELOW the map: candidates. The top of the screen is
                        // the plan, the bottom is options.
                        candidatesSection(day)
                        tomorrowSection()
                    } else {
                        // All: the map IS the screen, and it shows everything
                        // that is still in play. No day narrative here - that
                        // is what tapping a day is for.
                        mapSection(
                            pool: liveItems,
                            scopeKey: "all",
                            title: "Everywhere on this trip",
                            // The list right below names them, so the count
                            // would be saying it twice.
                            countsUnmapped: false
                        )
                        .id(Self.mapAnchor)
                        unmappedSection
                    }

                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 40)
            }
            .refreshable { await load(force: true) }
            .onAppear {
                scrollToMap = { proxy.scrollTo(Self.mapAnchor, anchor: .top) }
            }
            }
        }
    }

    /// Scroll target for `select`, so tapping a row brings the map to her.
    private static let mapAnchor = "trip-map"


    /// Search and Near me. Both came from the trip map, which no longer exists.
    private var filterBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.sunSecondary)
                TextField("Search this trip", text: $searchQuery)
                    .font(.system(size: 13, design: .serif))
                    .foregroundStyle(Color.sunText)
                    .autocorrectionDisabled()
                if !searchQuery.isEmpty {
                    Button { searchQuery = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.sunSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.sunSurface)
            .clipShape(Capsule())

            Button {
                nearMe.toggle()
                if nearMe && userLocation == nil { LocationService.shared.requestLocationForNearMe() }
                mapSelectedID = nil
            } label: {
                Text(nearMe ? "Near me" : "Near me")
                    .font(.system(size: 12, weight: .semibold, design: .serif))
                    .foregroundStyle(nearMe ? Color.sunBackground : Color.sunSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(nearMe ? Color(hex: "#3B82F6") : Color.sunSurface)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    // MARK: - Day strip

    private var dayStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) { selection = .all }
                    } label: {
                        Text("All")
                            .font(.system(size: 13, weight: .semibold, design: .serif))
                            .foregroundStyle(selection == .all ? Color.sunBackground : Color.sunText.opacity(0.7))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(selection == .all ? Color.sunAccent : Color.sunSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)

                    if let todayIndex = plans.firstIndex(where: { $0.dateString == tripToday }) {
                        Button {
                            withAnimation(.easeOut(duration: 0.15)) { selection = .day(todayIndex) }
                        } label: {
                            Text("Today")
                                .font(.system(size: 13, weight: .semibold, design: .serif))
                                .foregroundStyle(selectedDayIndex == todayIndex ? Color.sunBackground : Color.sunAccent)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 9)
                                .background(selectedDayIndex == todayIndex ? Color.sunAccent : Color.sunAccent.opacity(0.18))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                    ForEach(Array(plans.enumerated()), id: \.element.id) { index, plan in
                        let selected = index == selectedDayIndex
                        let today = plan.dateString == tripToday
                        let past = plan.dateString < tripToday
                        Button {
                            withAnimation(.easeOut(duration: 0.15)) { selection = .day(index) }
                        } label: {
                            VStack(spacing: 1) {
                                Text(weekday(plan.dateString))
                                    .font(.system(size: 10, weight: .semibold, design: .serif))
                                    .textCase(.uppercase)
                                    .opacity(0.7)
                                Text(shortDate(plan.dateString))
                                    .font(.system(size: 14, weight: .semibold, design: .serif))
                            }
                            .foregroundStyle(selected ? Color.sunBackground : Color.sunText.opacity(past ? 0.35 : 0.7))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(selected ? Color.sunAccent : Color.sunSurface)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(today && !selected ? Color.sunAccent.opacity(0.5) : .clear, lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        .id(index)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .background(Color.sunSurface.opacity(0.5))
            .onChange(of: plans.count) { _, _ in
                guard let index = selectedDayIndex else { return }
                proxy.scrollTo(index, anchor: .center)
            }
        }
    }

    // MARK: - Sections

    private func dayHeader(_ day: TripDayPlanner.DayPlan) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(longDate(day.dateString))
                .font(.system(size: 22, weight: .bold, design: .serif))
                .foregroundStyle(Color.sunAccent)
            Text([
                "Day \(day.dayNumber) of \(day.totalDays)",
                day.legCity.isEmpty ? nil : day.legCity,
            ].compactMap { $0 }.joined(separator: " - "))
                .font(.system(.caption, design: .serif))
                .foregroundStyle(Color.sunSecondary)
        }
    }

    /// The next thing with a real clock time still ahead of us. Only shown on
    /// today, and only when an exact time exists - a rough "afternoon" is not
    /// precise enough to promise something is next.
    private func upNext(in day: TripDayPlanner.DayPlan) -> TripDayPlanner.PlannedItem? {
        let now = Calendar.current.component(.hour, from: Date()) * 60
            + Calendar.current.component(.minute, from: Date())
        return day.timeline.first { $0.time.exact && $0.time.sortKey >= now }
    }

    private func upNextCard(_ planned: TripDayPlanner.PlannedItem) -> some View {
        Button { select(planned.item) } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text("Up next")
                    .font(.system(size: 10, weight: .semibold, design: .serif))
                    .textCase(.uppercase)
                    .foregroundStyle(Color.sunAccent)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if let label = planned.time.label {
                        Text(label)
                            .font(.system(size: 16, weight: .bold, design: .serif))
                            .foregroundStyle(Color.sunText)
                            .monospacedDigit()
                    }
                    Text(planned.item.name)
                        .font(.system(size: 18, weight: .bold, design: .serif))
                        .foregroundStyle(Color.sunText)
                        .multilineTextAlignment(.leading)
                }
                if let line = locationLine(planned.item) {
                    Text(line)
                        .font(.system(.caption, design: .serif))
                        .foregroundStyle(Color.sunSecondary)
                }
                directionsButton(planned.item)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color.sunAccent.opacity(0.12))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.sunAccent.opacity(0.3), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private func needsBookingCard(_ pending: [TripItem]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Still needs booking")
                .font(.system(size: 10, weight: .semibold, design: .serif))
                .textCase(.uppercase)
                .foregroundStyle(Color(hex: "#F97316"))
            ForEach(pending) { item in
                Button { select(item) } label: {
                    HStack(alignment: .top, spacing: 6) {
                        Text("-").foregroundStyle(Color.sunSecondary)
                        Text(item.name)
                            .font(.system(.subheadline, design: .serif))
                            .foregroundStyle(Color.sunText)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(hex: "#F97316").opacity(0.10))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "#F97316").opacity(0.3), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var isPastDay: Bool { (day?.dateString ?? "") < tripToday }

    private func sleepingCard(_ hotel: TripItem) -> some View {
        Button { select(hotel) } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(isPastDay ? "Stayed here" : "Sleeping tonight")
                    .font(.system(size: 10, weight: .semibold, design: .serif))
                    .textCase(.uppercase)
                    .foregroundStyle(Color(hex: "#3B82F6"))
                Text(hotel.name)
                    .font(.system(size: 17, weight: .bold, design: .serif))
                    .foregroundStyle(Color.sunText)
                    .multilineTextAlignment(.leading)
                if !hotel.address.isEmpty {
                    Text(hotel.address)
                        .font(.system(.caption, design: .serif))
                        .foregroundStyle(Color.sunSecondary)
                        .multilineTextAlignment(.leading)
                }
                if let line = hotel.confirmationLine {
                    Text(line)
                        .font(.system(.caption, design: .serif))
                        .foregroundStyle(Color(hex: "#34C759"))
                        .monospacedDigit()
                }
                directionsButton(hotel)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color(hex: "#3B82F6").opacity(0.10))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "#3B82F6").opacity(0.3), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .opacity(isPastDay ? 0.5 : 1)
        }
        .buttonStyle(.plain)
    }

    /// What is actually settled today. Confirmed only, by her instruction.
    @ViewBuilder
    private func confirmedSection(_ day: TripDayPlanner.DayPlan) -> some View {
        let confirmed = day.scheduled.filter { $0.item.status == .confirmed && matches($0.item) }
        let showsTime = confirmed.contains { $0.time.label != nil }
        let dayDone = day.dateString < tripToday

        if confirmed.isEmpty {
            Text("Nothing confirmed today.")
                .font(.system(.subheadline, design: .serif))
                .foregroundStyle(Color.sunSecondary)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(confirmed) { itemRow($0, showsTime: showsTime, dayDone: dayDone) }
            }
        }
    }

    /// Everything else on the day: planned but unconfirmed, plus the leg's
    /// candidates. Lives BELOW the map.
    @ViewBuilder
    private func candidatesSection(_ day: TripDayPlanner.DayPlan) -> some View {
        let rest = day.scheduled.filter { $0.item.status != .confirmed && matches($0.item) }
        let others = day.options.filter(matches)
        let showsTime = rest.contains { $0.time.label != nil }

        if !rest.isEmpty || !others.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text(rest.isEmpty ? "Nearby, not scheduled" : "Not confirmed")
                    .font(.system(size: 10, weight: .semibold, design: .serif))
                    .textCase(.uppercase)
                    .foregroundStyle(Color.sunSecondary)
                    .padding(.bottom, 2)

                ForEach(rest) { itemRow($0, showsTime: showsTime, dayDone: false) }
                ForEach(others) { item in
                    itemRow(
                        TripDayPlanner.PlannedItem(item: item, time: TripTime.empty),
                        showsTime: false,
                        dayDone: false
                    )
                }
            }
        }
    }

    private func itemRow(_ planned: TripDayPlanner.PlannedItem, showsTime: Bool, dayDone: Bool) -> some View {
        let item = planned.item
        let done = dayDone && item.status == .confirmed
        return Button { select(item) } label: {
            HStack(alignment: .top, spacing: 8) {
                if showsTime {
                    // A rough word renders as the word, in a dimmer style. It
                    // is never shown as the clock time it was anchored to.
                    Text(planned.time.label ?? "")
                        .font(.system(size: planned.time.exact ? 13 : 11, weight: .regular, design: .serif))
                        .foregroundStyle(planned.time.exact ? Color.sunText : Color.sunSecondary)
                        .monospacedDigit()
                        .frame(width: 62, alignment: .leading)
                }

                Circle()
                    .fill(item.status?.color ?? Color.sunSecondary)
                    .frame(width: 8, height: 8)
                    .padding(.top, 6)

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name)
                        .font(.system(size: 15, weight: .semibold, design: .serif))
                        .foregroundStyle(Color.sunText)
                        .strikethrough(done, color: Color.sunSecondary)
                        .multilineTextAlignment(.leading)
                    // One short fragment, never the whole note. Elisa,
                    // 2026-09-06: "try to keep each item description to 1 short
                    // sentence fragment or less." The full note is one tap away
                    // in the detail sheet, so nothing is lost, it is just not
                    // in the way when she is scanning the day.
                    if let fragment = terseNote(item) {
                        Text(fragment)
                            .font(.system(size: 12, design: .serif))
                            .foregroundStyle(Color.sunText.opacity(0.6))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    if let line = item.confirmationLine {
                        Text(line)
                            .font(.system(size: 12, weight: .semibold, design: .serif))
                            .foregroundStyle(Color(hex: "#34C759"))
                            .monospacedDigit()
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 8)
            .opacity(done ? 0.4 : 1)
        }
        .buttonStyle(.plain)
    }

    /// The trip on a map, filterable by type, leg, status, search and Near me.
    ///
    /// This is the screen, not a section of the day. It renders on All, on a
    /// day, and on a day with nothing on it. Elisa, 2026-09-08: "the whole map
    /// should be visible no matter if things are or not assigned."
    ///
    /// Undated candidates already fan out across every day of their leg in
    /// TripDayPlanner, so a day's pins are effectively the leg's pins - which
    /// is what "around the areas where I'll be going" means.
    @ViewBuilder
    private func mapSection(pool: [TripItem], scopeKey: String, title: String, countsUnmapped: Bool = true) -> some View {
        let shown = pool.filter(matches)
        // One pin per item, plus one per chain branch (the server decides both).
        let annotations = shown.flatMap(\.mapAnnotations)
        let unmapped = shown.filter { !$0.hasCoordinates }.count

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 10, weight: .semibold, design: .serif))
                    .textCase(.uppercase)
                    .foregroundStyle(Color.sunSecondary)
                Spacer()
                Button {
                    confirmedOnly.toggle()
                    mapSelectedID = nil
                } label: {
                    Text("Confirmed only")
                        .font(.system(size: 11, weight: .semibold, design: .serif))
                        .foregroundStyle(confirmedOnly ? Color.sunBackground : Color.sunSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(confirmedOnly ? Color(hex: "#22C55E") : Color.sunSurface)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                if assistantResponse != nil {
                    Button("Clear ask") { assistantResponse = nil }
                        .font(.system(size: 11, design: .serif))
                        .foregroundStyle(Color.sunAccent)
                }
                if !activeTypes.isEmpty {
                    Button("Clear") { activeTypes.removeAll() }
                        .font(.system(size: 11, design: .serif))
                        .foregroundStyle(Color.sunAccent)
                }
            }

            typeToggles(in: pool)

            ZStack(alignment: .topTrailing) {
                TripMKMap(
                    annotations: annotations,
                    filterKey: "\(scopeKey)|\(activeTypes.map(\.rawValue).sorted().joined(separator: ","))|\(activeLegs.sorted().joined(separator: ","))|\(confirmedOnly)|\(nearMe)|\(searchQuery)|\((assistantResponse?.matchedItemIds ?? []).joined(separator: ","))",
                    selectedID: $mapSelectedID,
                    bridge: mapBridge,
                    // A branch pin opens its own item, not a copy of it.
                    onOpenDetail: { tapped in
                        detailItem = items.first { $0.id == TripItem.placeID(of: tapped.id) } ?? tapped
                    },
                    onOpenCluster: { tapped in
                        var seen = Set<String>()
                        let members = tapped
                            .map { t in items.first { $0.id == TripItem.placeID(of: t.id) } ?? t }
                            .filter { seen.insert($0.id).inserted }
                        clusterItems = ClusterSelection(items: members)
                    },
                    // The assistant's matches used to light up on the trip
                    // map. That map is gone; the capability lives in
                    // TripMKMap and just needed wiring here.
                    highlightedItemIds: Set(assistantResponse?.matchedItemIds ?? [])
                )
                .frame(height: 300)
                .clipShape(RoundedRectangle(cornerRadius: 14))

                Button { mapBridge.fitAll() } label: {
                    Image(systemName: "scope")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.sunAccent)
                        .frame(width: 32, height: 32)
                        .background(Color.sunSurface.opacity(0.9))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .padding(8)
            }

            // Never silently drop pins. An item with no coordinate is not on
            // the map, and she should know how many rather than wonder.
            if unmapped > 0, countsUnmapped {
                Text("\(unmapped) not on the map yet (no location found)")
                    .font(.system(size: 11, design: .serif))
                    .foregroundStyle(Color.sunSecondary)
            }
        }
    }

    /// On All, the items the map cannot place. Without this a place with no
    /// geocode is counted and then unreachable.
    @ViewBuilder
    private var unmappedSection: some View {
        let missing = liveItems.filter(matches).filter { $0.latitude == nil || $0.longitude == nil }
        if !missing.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text("Not on the map")
                    .font(.system(size: 10, weight: .semibold, design: .serif))
                    .textCase(.uppercase)
                    .foregroundStyle(Color.sunSecondary)
                    .padding(.bottom, 2)
                ForEach(missing) { item in
                    itemRow(
                        TripDayPlanner.PlannedItem(item: item, time: TripTime.empty),
                        showsTime: false,
                        dayDone: false
                    )
                }
            }
        }
    }

    /// Only the types actually present on this day get a chip - a Ferry toggle
    /// on a Utah ski weekend is noise.
    private func typeToggles(in pool: [TripItem]) -> some View {
        let present = TripItem.ItemType.allCases.filter { type in
            pool.contains { $0.type == type }
        }
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                // Types first. Legs used to lead, and on a four-leg trip they
                // filled the row and pushed Restaurant / Hotel / Activity off
                // the right edge - the toggle she actually reaches for.
                ForEach(present, id: \.self) { type in
                    let on = activeTypes.contains(type)
                    Button {
                        if on { activeTypes.remove(type) } else { activeTypes.insert(type) }
                        mapSelectedID = nil
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: type.sfSymbol)
                                .font(.system(size: 10, weight: .semibold))
                            Text(type.rawValue)
                                .font(.system(size: 12, weight: .medium, design: .serif))
                        }
                        .foregroundStyle(on ? Color.sunBackground : type.color)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(on ? type.color : Color.sunSurface)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                ForEach(legs, id: \.self) { leg in
                    let on = activeLegs.contains(leg)
                    Button {
                        if on { activeLegs.remove(leg) } else { activeLegs.insert(leg) }
                        mapSelectedID = nil
                    } label: {
                        Text(leg)
                            .font(.system(size: 12, weight: .medium, design: .serif))
                            .foregroundStyle(on ? Color.sunBackground : Color(hex: "#818CF8"))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(on ? Color(hex: "#6366F1") : Color.sunSurface)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 1)
        }
    }

    @ViewBuilder
    private func tomorrowSection() -> some View {
        if let index = selectedDayIndex, index + 1 < plans.count {
            let next = plans[index + 1]
            let names = next.scheduled.prefix(3).map(\.item.name).joined(separator: ", ")
            Button { withAnimation(.easeOut(duration: 0.15)) { selection = .day(index + 1) } } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Next day")
                        .font(.system(size: 10, weight: .semibold, design: .serif))
                        .textCase(.uppercase)
                        .foregroundStyle(Color.sunSecondary.opacity(0.7))
                    Text(names.isEmpty ? "Nothing scheduled yet" : names)
                        .font(.system(.caption, design: .serif))
                        .foregroundStyle(Color.sunSecondary)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 12)
            }
            .buttonStyle(.plain)
            .overlay(Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1), alignment: .top)
        }
    }


    private var offlineBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash")
            Text("Offline - showing the last synced plan. Maps and directions still open.")
                .multilineTextAlignment(.leading)
        }
        .font(.system(.caption, design: .serif))
        .foregroundStyle(Color.sunBackground)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.sunAccent)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.title)
                .foregroundStyle(Color.sunSecondary)
            Text(loadErrorMessage ?? "Nothing on this trip yet")
                .font(.system(.subheadline, design: .serif))
                .foregroundStyle(Color.sunText)
            Text("Add a hotel, restaurant or activity in Notion and it shows up here, with or without a date.")
                .font(.system(.caption, design: .serif))
                .foregroundStyle(Color.sunSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    // MARK: - Shared bits

    /// The first clause of a note, capped hard. Cuts at the first sentence end
    /// or the first separator, so it reads as a fragment rather than a
    /// truncated sentence.
    private func terseNote(_ item: TripItem) -> String? {
        let note = item.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !note.isEmpty else {
            // No note: fall back to the venue, which is often the useful bit.
            let venue = item.venue.trimmingCharacters(in: .whitespacesAndNewlines)
            return venue.isEmpty || venue == item.name ? nil : venue
        }
        var fragment = note
        if let cut = fragment.rangeOfCharacter(from: CharacterSet(charactersIn: ".;\n")) {
            fragment = String(fragment[fragment.startIndex..<cut.lowerBound])
        }
        fragment = fragment.trimmingCharacters(in: .whitespaces)
        if fragment.count > 62 {
            fragment = String(fragment.prefix(62)).trimmingCharacters(in: .whitespaces) + "..."
        }
        return fragment.isEmpty ? nil : fragment
    }

    private func locationLine(_ item: TripItem) -> String? {
        if !item.address.isEmpty { return item.address }
        let parts = [item.type?.rawValue, item.venue.isEmpty || item.venue == item.name ? nil : item.venue]
        let line = parts.compactMap { $0 }.joined(separator: " - ")
        return line.isEmpty ? nil : line
    }

    /// Directions work offline: Apple Maps takes the handoff and the address or
    /// coordinate is already on the device.
    private func directionsButton(_ item: TripItem) -> some View {
        Button {
            openDirections(item)
        } label: {
            Label("Directions", systemImage: "arrow.triangle.turn.up.right.circle.fill")
                .font(.system(.caption, design: .serif, weight: .semibold))
                .foregroundStyle(Color.sunAccent)
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
    }

    private func openDirections(_ item: TripItem) {
        if let lat = item.latitude, let lon = item.longitude {
            let mapItem = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon)))
            mapItem.name = item.name
            mapItem.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
            return
        }
        // No coordinate: hand Apple Maps the best text we have rather than
        // silently doing nothing.
        let query = [item.address.isEmpty ? item.venue.isEmpty ? item.name : item.venue : item.address, item.legCity]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "http://maps.apple.com/?q=\(encoded)") else { return }
        UIApplication.shared.open(url)
    }

    private func weekday(_ dateString: String) -> String { formatted(dateString, "EEE") }
    private func shortDate(_ dateString: String) -> String { formatted(dateString, "MMM d") }
    private func longDate(_ dateString: String) -> String { formatted(dateString, "EEEE, MMMM d") }

    private func formatted(_ dateString: String, _ pattern: String) -> String {
        let parser = DateFormatter()
        parser.dateFormat = "yyyy-MM-dd"
        parser.timeZone = TimeZone(identifier: "UTC")
        guard let date = parser.date(from: dateString) else { return dateString }
        let out = DateFormatter()
        out.dateFormat = pattern
        out.timeZone = TimeZone(identifier: "UTC")
        return out.string(from: date)
    }

    // MARK: - Load

    private func load(force: Bool = false) async {
        do {
            let result = try await TravelService.shared.fetchTripItems(tripId: trip.id, force: force)
            let withCoords = TravelService.shared.applyCachedCoordinates(result.items, tripId: trip.id)
            apply(withCoords, offline: result.isOffline)
            isLoading = false

            // Fresh pins need the network, so they come after the day is already
            // on screen. Without them the day still renders from the last answer.
            let geocoded = await TravelService.shared.geocodeItems(withCoords, tripId: trip.id)
            apply(geocoded, offline: result.isOffline)
        } catch {
            isLoading = false
            if items.isEmpty { loadErrorMessage = "Could not load this trip: \(error.localizedDescription)" }
        }
    }

    private func apply(_ newItems: [TripItem], offline: Bool) {
        let previousDate = day?.dateString
        items = newItems
        plans = TripDayPlanner.plans(for: newItems)
        isOffline = offline
        // Keep whatever she was looking at across a refresh. All stays All: it
        // is the default and nothing here may quietly move her off it. A day
        // that no longer exists falls back to All, never to a day she did not
        // pick.
        if let previousDate {
            selection = plans.firstIndex(where: { $0.dateString == previousDate }).map { .day($0) } ?? .all
        }
    }
}

/// Wrapper so a plain array can drive `.sheet(item:)`.
struct ClusterSelection: Identifiable {
    let id = UUID()
    let items: [TripItem]
}

/// Shown when several pins sit on the same coordinate and zooming can never
/// separate them. Six Park City items share the "Montage Deer Valley" geocode,
/// so without this those items are simply unreachable on the map.
struct ClusterPickerSheet: View {
    let items: [TripItem]
    let onSelect: (TripItem) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(items) { item in
                Button { onSelect(item) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: item.type?.sfSymbol ?? "mappin")
                            .font(.system(size: 13))
                            .foregroundStyle(item.type?.color ?? Color.sunSecondary)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name)
                                .font(.system(.subheadline, design: .serif))
                                .foregroundStyle(Color.sunText)
                                .multilineTextAlignment(.leading)
                            if let status = item.status {
                                Text(status.rawValue)
                                    .font(.system(.caption2, design: .serif))
                                    .foregroundStyle(status.color)
                            }
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.sunSecondary)
                    }
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.sunSurface)
            }
            .scrollContentBackground(.hidden)
            .background(Color.sunBackground)
            .navigationTitle("\(items.count) in the same spot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(Color.sunSurface, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }.foregroundStyle(Color.sunAccent)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
