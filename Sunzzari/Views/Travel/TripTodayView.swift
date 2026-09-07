import SwiftUI
import CoreLocation
import MapKit

/// The during-the-trip screen: one day at a time, opening on today.
///
/// This exists because the map and the trip list answer "what is this trip",
/// and on a Thursday morning in Park City the question is "what is happening
/// today". Everything here is ordered for a ten-second skim, and everything it
/// needs is on disk, so it works with no signal.
struct TripTodayView: View {
    let trip: Trip

    @State private var items: [TripItem] = []
    @State private var plans: [TripDayPlanner.DayPlan] = []
    @State private var selectedIndex: Int = 0
    @State private var isLoading = true
    @State private var isRefreshing = false
    @State private var isOffline = false
    @State private var loadErrorMessage: String?
    @State private var detailItem: TripItem?
    @State private var showItinerary = false
    @State private var userLocation: CLLocation?
    @State private var activeTypes: Set<TripItem.ItemType> = []
    @State private var mapSelectedID: String?
    @State private var mapBridge = TripMapBridge()
    @State private var showQuickAdd = false
    @State private var clusterItems: ClusterSelection?

    private var day: TripDayPlanner.DayPlan? {
        plans.indices.contains(selectedIndex) ? plans[selectedIndex] : nil
    }

    private var isToday: Bool { day?.dateString == TripDayPlanner.todayString }

    private var itineraryURLString: String {
        if let u = trip.itineraryURL, !u.isEmpty { return u }
        return "https://elisa-travel-map.vercel.app/\(trip.id.replacingOccurrences(of: "-", with: ""))/itinerary"
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.sunBackground.ignoresSafeArea()

            if isLoading && items.isEmpty {
                ProgressView().tint(Color.sunAccent)
            } else if plans.isEmpty {
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
                Button { showQuickAdd = true } label: {
                    Image(systemName: "plus").foregroundStyle(Color.sunAccent)
                }
                .disabled(day == nil)
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { TripDetailView(trip: trip) } label: {
                    Image(systemName: "map").foregroundStyle(Color.sunAccent)
                }
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
        .sheet(item: $clusterItems) { selection in
            ClusterPickerSheet(items: selection.items) { item in
                clusterItems = nil
                detailItem = item
            }
        }
        .sheet(isPresented: $showItinerary) { ItineraryWebView(urlString: itineraryURLString) }
        .sheet(isPresented: $showQuickAdd) {
            if let day {
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
            dayStrip

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if isOffline { offlineBanner }

                    if let day {
                        dayHeader(day)
                        if isToday, let next = upNext(in: day) { upNextCard(next) }
                        if !day.needsBooking.isEmpty { needsBookingCard(day.needsBooking) }
                        if let hotel = day.hotel { sleepingCard(hotel) }
                        scheduleSection(day)
                        nearbySection(day)
                        mapSection(day)
                        tomorrowSection()
                    }

                    footer
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 40)
            }
            .refreshable { await load(force: true) }
        }
    }

    // MARK: - Day strip

    private var dayStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(plans.enumerated()), id: \.element.id) { index, plan in
                        let selected = index == selectedIndex
                        let today = plan.dateString == TripDayPlanner.todayString
                        Button {
                            withAnimation(.easeOut(duration: 0.15)) { selectedIndex = index }
                        } label: {
                            VStack(spacing: 1) {
                                Text(weekday(plan.dateString))
                                    .font(.system(size: 10, weight: .semibold, design: .serif))
                                    .textCase(.uppercase)
                                    .opacity(0.7)
                                Text(shortDate(plan.dateString))
                                    .font(.system(size: 14, weight: .semibold, design: .serif))
                            }
                            .foregroundStyle(selected ? Color.sunBackground : Color.sunText.opacity(0.7))
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
                proxy.scrollTo(selectedIndex, anchor: .center)
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
        Button { detailItem = planned.item } label: {
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
                Button { detailItem = item } label: {
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

    private func sleepingCard(_ hotel: TripItem) -> some View {
        Button { detailItem = hotel } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text("Sleeping tonight")
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
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func scheduleSection(_ day: TripDayPlanner.DayPlan) -> some View {
        if day.isEmpty {
            Text("Nothing scheduled. Anything below is fair game.")
                .font(.system(.subheadline, design: .serif))
                .foregroundStyle(Color.sunSecondary)
        } else {
            // Drop the time gutter entirely when nothing on this day has a
            // time. An empty 62pt column on every row is just dead space, and
            // most days currently have no times at all.
            let showsTime = day.scheduled.contains { $0.time.label != nil }

            VStack(alignment: .leading, spacing: 0) {
                ForEach(day.timeline) { itemRow($0, showsTime: showsTime) }

                // Only worth a heading when there is a timeline to distinguish
                // it from. With no times entered, everything lands here and the
                // label would just sit above the whole day saying nothing.
                if !day.anytime.isEmpty && !day.timeline.isEmpty {
                    Text("Anytime today")
                        .font(.system(size: 10, weight: .semibold, design: .serif))
                        .textCase(.uppercase)
                        .foregroundStyle(Color.sunSecondary)
                        .padding(.top, 14)
                        .padding(.bottom, 4)
                }
                ForEach(day.anytime) { itemRow($0, showsTime: showsTime) }
            }
        }
    }

    private func itemRow(_ planned: TripDayPlanner.PlannedItem, showsTime: Bool) -> some View {
        let item = planned.item
        return Button { detailItem = item } label: {
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
                        .multilineTextAlignment(.leading)
                    if let line = locationLine(item) {
                        Text(line)
                            .font(.system(size: 12, design: .serif))
                            .foregroundStyle(Color.sunSecondary)
                            .multilineTextAlignment(.leading)
                    }
                    if !item.notes.isEmpty {
                        Text(item.notes)
                            .font(.system(size: 12, design: .serif))
                            .foregroundStyle(Color.sunText.opacity(0.65))
                            .multilineTextAlignment(.leading)
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
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func nearbySection(_ day: TripDayPlanner.DayPlan) -> some View {
        let nearby = nearbyItems(day)
        if !nearby.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Near you now")
                    .font(.system(size: 10, weight: .semibold, design: .serif))
                    .textCase(.uppercase)
                    .foregroundStyle(Color.sunSecondary)
                ForEach(nearby, id: \.0.id) { item, meters in
                    Button { detailItem = item } label: {
                        HStack {
                            Text(item.name)
                                .font(.system(.subheadline, design: .serif))
                                .foregroundStyle(Color.sunText)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 8)
                            Text(distanceLabel(meters))
                                .font(.system(.caption, design: .serif))
                                .foregroundStyle(Color.sunAccent)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.sunSurface.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    /// Candidates within walking-and-a-bit distance, closest first. Only shown
    /// when a location fix already exists - this screen never prompts.
    private func nearbyItems(_ day: TripDayPlanner.DayPlan) -> [(TripItem, CLLocationDistance)] {
        guard let loc = userLocation else { return [] }
        let scheduledIDs = Set(day.scheduled.map(\.id))
        return day.options
            .filter { !scheduledIDs.contains($0.id) }
            .compactMap { item -> (TripItem, CLLocationDistance)? in
                guard let lat = item.latitude, let lon = item.longitude else { return nil }
                let d = loc.distance(from: CLLocation(latitude: lat, longitude: lon))
                return d <= 5000 ? (item, d) : nil
            }
            .sorted { $0.1 < $1.1 }
            .prefix(5)
            .map { $0 }
    }

    /// Everything on this day, on a map, filterable by type.
    ///
    /// Replaces the old "if you have time" chip wall, which rendered Park City's
    /// 20 undated candidates as an undifferentiated block of pills. "What else
    /// is around" is a spatial question and the app already has a good map.
    ///
    /// Undated candidates already fan out across every day of their leg in
    /// TripDayPlanner, so the day's pins are effectively the leg's pins - which
    /// is what "around the areas where I'll be going" means.
    @ViewBuilder
    private func mapSection(_ day: TripDayPlanner.DayPlan) -> some View {
        let pool = day.scheduled.map(\.item) + day.options
        let shown = pool.filter { activeTypes.isEmpty || ($0.type.map { activeTypes.contains($0) } ?? false) }
        let annotations = shown.compactMap { item -> TripItemAnnotation? in
            guard let lat = item.latitude, let lon = item.longitude else { return nil }
            return TripItemAnnotation(item: item, coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon))
        }
        let unmapped = shown.count - annotations.count

        if !pool.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Around you")
                        .font(.system(size: 10, weight: .semibold, design: .serif))
                        .textCase(.uppercase)
                        .foregroundStyle(Color.sunSecondary)
                    Spacer()
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
                        filterKey: "\(day.dateString)|\(activeTypes.map(\.rawValue).sorted().joined(separator: ","))",
                        selectedID: $mapSelectedID,
                        bridge: mapBridge,
                        onOpenDetail: { detailItem = $0 },
                        onOpenCluster: { clusterItems = ClusterSelection(items: $0) }
                    )
                    .frame(height: 260)
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
                if unmapped > 0 {
                    Text("\(unmapped) not on the map yet (no location found)")
                        .font(.system(size: 11, design: .serif))
                        .foregroundStyle(Color.sunSecondary)
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
            }
            .padding(.horizontal, 1)
        }
    }

    @ViewBuilder
    private func tomorrowSection() -> some View {
        if selectedIndex + 1 < plans.count {
            let next = plans[selectedIndex + 1]
            let names = next.scheduled.prefix(3).map(\.item.name).joined(separator: ", ")
            Button { withAnimation(.easeOut(duration: 0.15)) { selectedIndex += 1 } } label: {
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

    private var footer: some View {
        Button { showItinerary = true } label: {
            Text("Open the full itinerary")
                .font(.system(.caption, design: .serif))
                .foregroundStyle(Color.sunAccent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.sunSurface)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .padding(.top, 8)
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
            Text(loadErrorMessage ?? "No scheduled days yet")
                .font(.system(.subheadline, design: .serif))
                .foregroundStyle(Color.sunText)
            Text("Items need a date and a status of Confirmed, Assigned or Reservation Pending to show up here.")
                .font(.system(.caption, design: .serif))
                .foregroundStyle(Color.sunSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    // MARK: - Shared bits

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

    private func distanceLabel(_ meters: CLLocationDistance) -> String {
        meters < 1000 ? "\(Int(meters))m" : String(format: "%.1fkm", meters / 1000)
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
            let withCoords = TravelService.shared.applyCachedCoordinates(result.items)
            apply(withCoords, offline: result.isOffline)
            isLoading = false

            // Geocoding needs the network, so it comes after the day is already
            // on screen. Without it the day still renders; only pin-accurate
            // directions and the Near You list wait.
            let geocoded = await TravelService.shared.geocodeItems(withCoords, tripLocation: trip.location)
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
        // Keep whatever day she was looking at across a refresh; only choose
        // one on the first load.
        if let previousDate, let index = plans.firstIndex(where: { $0.dateString == previousDate }) {
            selectedIndex = index
        } else {
            selectedIndex = TripDayPlanner.openingIndex(in: plans)
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
