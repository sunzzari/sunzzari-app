import SwiftUI
import MapKit

// MARK: - Annotation model

final class RestaurantAnnotation: NSObject, MKAnnotation {
    let restaurant: Restaurant
    @objc dynamic var coordinate: CLLocationCoordinate2D
    var title: String? { restaurant.name }

    init(restaurant: Restaurant, coordinate: CLLocationCoordinate2D) {
        self.restaurant = restaurant
        self.coordinate = coordinate
    }
}

// MARK: - Bridge (SwiftUI → UIKit imperative calls)

final class MapBridge {
    weak var mapView: MKMapView?

    func fitAll(animated: Bool = true) {
        guard let mv = mapView else { return }
        let anns = mv.annotations.filter { !($0 is MKUserLocation) }
        guard !anns.isEmpty else { return }
        mv.showAnnotations(anns, animated: animated)
    }

    func center(on coord: CLLocationCoordinate2D, metersSpan: CLLocationDistance = 4000) {
        guard let mv = mapView else { return }
        mv.setRegion(
            MKCoordinateRegion(center: coord, latitudinalMeters: metersSpan, longitudinalMeters: metersSpan),
            animated: true
        )
    }
}

// MARK: - UIViewRepresentable

struct RestaurantMKMap: UIViewRepresentable {
    let annotations: [RestaurantAnnotation]
    let allRestaurantCount: Int
    let filterKey: String
    @Binding var selectedID: String?
    let bridge: MapBridge

    func makeCoordinator() -> Coordinator { Coordinator(selectedID: $selectedID) }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsUserLocation = true
        map.mapType = .standard
        map.setRegion(
            MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 34.05, longitude: -118.24),
                latitudinalMeters: 60_000, longitudinalMeters: 60_000
            ),
            animated: false
        )
        map.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: "restaurant")
        map.register(
            MKMarkerAnnotationView.self,
            forAnnotationViewWithReuseIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier
        )
        bridge.mapView = map
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.isUpdating = true
        defer { coordinator.isUpdating = false }

        // Sync annotations
        let existing = Set(map.annotations.compactMap { ($0 as? RestaurantAnnotation)?.restaurant.id })
        let desired = Set(annotations.map(\.restaurant.id))

        let toRemove = map.annotations.filter {
            guard let ra = $0 as? RestaurantAnnotation else { return false }
            return !desired.contains(ra.restaurant.id)
        }
        if !toRemove.isEmpty { map.removeAnnotations(toRemove) }

        let toAdd = annotations.filter { !existing.contains($0.restaurant.id) }
        if !toAdd.isEmpty {
            map.addAnnotations(toAdd)

            // Fit all pins the first time the full set is placed (initial geocoding complete)
            let placed = map.annotations.filter { $0 is RestaurantAnnotation }.count
            if !coordinator.didFitAll && allRestaurantCount > 0 && placed >= allRestaurantCount {
                coordinator.didFitAll = true
                coordinator.lastFilterKey = filterKey
                let anns = map.annotations.filter { !($0 is MKUserLocation) }
                DispatchQueue.main.async { map.showAnnotations(anns, animated: true) }
            }
        }

        // Re-fit when filter changes (after initial geocoding is done)
        if coordinator.didFitAll && filterKey != coordinator.lastFilterKey {
            coordinator.lastFilterKey = filterKey
            DispatchQueue.main.async {
                let anns = map.annotations.filter { !($0 is MKUserLocation) }
                if !anns.isEmpty { map.showAnnotations(anns, animated: true) }
                else {
                    // All filtered out — zoom to default LA view
                    map.setRegion(
                        MKCoordinateRegion(
                            center: CLLocationCoordinate2D(latitude: 34.05, longitude: -118.24),
                            latitudinalMeters: 60_000, longitudinalMeters: 60_000
                        ),
                        animated: true
                    )
                }
            }
        }

        // Sync selection state
        if let id = selectedID {
            let alreadySelected = map.selectedAnnotations.contains {
                ($0 as? RestaurantAnnotation)?.restaurant.id == id
            }
            if !alreadySelected,
               let ann = map.annotations.first(where: { ($0 as? RestaurantAnnotation)?.restaurant.id == id }) {
                map.selectAnnotation(ann, animated: true)
            }
        } else {
            map.selectedAnnotations.forEach { map.deselectAnnotation($0, animated: false) }
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, MKMapViewDelegate {
        @Binding var selectedID: String?
        var isUpdating = false
        var didFitAll = false
        var lastFilterKey: String = ""
        private var didCenterOnUser = false

        init(selectedID: Binding<String?>) {
            _selectedID = selectedID
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation { return nil }

            if let cluster = annotation as? MKClusterAnnotation {
                let v = mapView.dequeueReusableAnnotationView(
                    withIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier,
                    for: cluster
                ) as! MKMarkerAnnotationView
                v.markerTintColor = UIColor(red: 0.984, green: 0.749, blue: 0.141, alpha: 1) // #FBBF24
                v.glyphText = "\(cluster.memberAnnotations.count)"
                v.titleVisibility = .hidden
                v.subtitleVisibility = .hidden
                return v
            }

            guard let ra = annotation as? RestaurantAnnotation else { return nil }
            let v = mapView.dequeueReusableAnnotationView(
                withIdentifier: "restaurant",
                for: annotation
            ) as! MKMarkerAnnotationView
            v.clusteringIdentifier = "restaurant"
            v.canShowCallout = false
            v.titleVisibility = .hidden
            v.subtitleVisibility = .hidden
            v.glyphText = "🍽️"
            if let pref = ra.restaurant.preference {
                v.markerTintColor = UIColor(Color(hex: pref.colorHex))
            } else {
                v.markerTintColor = .systemGray2
            }
            return v
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            guard !isUpdating else { return }
            if let ra = view.annotation as? RestaurantAnnotation {
                selectedID = ra.restaurant.id
            }
        }

        func mapView(_ mapView: MKMapView, didDeselect view: MKAnnotationView) {
            guard !isUpdating else { return }
            selectedID = nil
        }

        func mapView(_ mapView: MKMapView, didUpdate userLocation: MKUserLocation) {
            guard !didCenterOnUser else { return }
            guard !mapView.annotations.contains(where: { $0 is RestaurantAnnotation }) else { return }
            didCenterOnUser = true
            mapView.setRegion(
                MKCoordinateRegion(
                    center: userLocation.coordinate,
                    latitudinalMeters: 8_000, longitudinalMeters: 8_000
                ),
                animated: true
            )
        }
    }
}

// MARK: - RestaurantMapView

struct RestaurantMapView: View {
    let restaurants: [Restaurant]

    @State private var pins: [String: CLLocationCoordinate2D] = [:]
    @State private var selectedID: String?
    @State private var bridge = MapBridge()

    // Filters
    @State private var showBeenThereOnly = false
    @State private var selectedLocations: Set<String> = []
    @State private var selectedPreferences: Set<String> = [] // pref rawValue or "Unrated"

    private var uniqueLocations: [String] {
        Array(Set(restaurants.map(\.location).filter { !$0.isEmpty })).sorted()
    }

    private var hasActiveFilters: Bool {
        showBeenThereOnly || !selectedLocations.isEmpty || !selectedPreferences.isEmpty
    }

    private var filteredRestaurants: [Restaurant] {
        restaurants.filter { r in
            let beenOK = !showBeenThereOnly || r.beenThere
            let locOK = selectedLocations.isEmpty || selectedLocations.contains(r.location)
            let prefOK = selectedPreferences.isEmpty ||
                selectedPreferences.contains(r.preference?.rawValue ?? "Unrated")
            return beenOK && locOK && prefOK
        }
    }

    private var annotations: [RestaurantAnnotation] {
        pins.compactMap { id, coord in
            filteredRestaurants.first { $0.id == id }.map {
                RestaurantAnnotation(restaurant: $0, coordinate: coord)
            }
        }
    }

    private var filterKey: String {
        let locs = selectedLocations.sorted().joined(separator: ",")
        let prefs = selectedPreferences.sorted().joined(separator: ",")
        return "\(showBeenThereOnly)|\(locs)|\(prefs)"
    }

    private var selectedRestaurant: Binding<Restaurant?> {
        Binding(
            get: { restaurants.first { $0.id == selectedID } },
            set: { r in selectedID = r?.id }
        )
    }

    var body: some View {
        ZStack {
            // Map — full screen
            RestaurantMKMap(
                annotations: annotations,
                allRestaurantCount: restaurants.count,
                filterKey: filterKey,
                selectedID: $selectedID,
                bridge: bridge
            )
            .ignoresSafeArea()

            // Top filter bar
            VStack(spacing: 0) {
                filterBar
                Spacer()
            }

            // Bottom overlays: rating legend (left) + locate me (right)
            VStack {
                Spacer()
                HStack(alignment: .bottom, spacing: 0) {
                    ratingLegend
                        .padding(.leading, 16)
                    Spacer()
                    locateMeButton
                        .padding(.trailing, 16)
                }
                .padding(.bottom, 32)
            }
        }
        .navigationTitle("Map")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: selectedRestaurant) { r in
            restaurantCallout(r)
                .presentationDetents([.fraction(0.35)])
                .presentationDragIndicator(.visible)
        }
        .task { await geocodeAll() }
    }

    // MARK: - Top filter bar

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Visited toggle
                filterChip(label: "Visited", icon: "checkmark", isActive: showBeenThereOnly) {
                    showBeenThereOnly.toggle()
                }

                // Divider
                if !uniqueLocations.isEmpty {
                    Rectangle()
                        .fill(Color.white.opacity(0.15))
                        .frame(width: 1, height: 16)

                    // Location chips
                    ForEach(uniqueLocations, id: \.self) { loc in
                        filterChip(label: loc, isActive: selectedLocations.contains(loc)) {
                            if selectedLocations.contains(loc) { selectedLocations.remove(loc) }
                            else { selectedLocations.insert(loc) }
                        }
                    }
                }

                // Clear All
                if hasActiveFilters {
                    Button {
                        showBeenThereOnly = false
                        selectedLocations = []
                        selectedPreferences = []
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
            .padding(.vertical, 10)
        }
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

    // MARK: - Rating legend (bottom-left)

    private var ratingLegend: some View {
        let anyActive = !selectedPreferences.isEmpty

        return VStack(alignment: .leading, spacing: 5) {
            Text("RATING")
                .font(.system(size: 10, weight: .semibold, design: .serif))
                .foregroundStyle(Color.white.opacity(0.4))
                .tracking(0.8)
                .padding(.bottom, 1)

            ForEach(Restaurant.Preference.allCases, id: \.self) { pref in
                let isActive = selectedPreferences.contains(pref.rawValue)
                let dimmed = anyActive && !isActive

                Button {
                    if selectedPreferences.contains(pref.rawValue) { selectedPreferences.remove(pref.rawValue) }
                    else { selectedPreferences.insert(pref.rawValue) }
                } label: {
                    HStack(spacing: 7) {
                        ZStack {
                            Circle()
                                .fill(Color(hex: pref.colorHex))
                                .frame(width: 10, height: 10)
                            if isActive {
                                Circle()
                                    .stroke(Color(hex: pref.colorHex), lineWidth: 1.5)
                                    .frame(width: 15, height: 15)
                            }
                        }
                        .frame(width: 18, height: 18)
                        Text(pref.rawValue)
                            .font(.system(size: 12, weight: .medium, design: .serif))
                            .foregroundStyle(isActive ? Color.white : Color.white.opacity(0.7))
                    }
                }
                .buttonStyle(.plain)
                .opacity(dimmed ? 0.3 : 1)
            }

            // Unrated row
            let unratedActive = selectedPreferences.contains("Unrated")
            let unratedDimmed = anyActive && !unratedActive

            Button {
                if selectedPreferences.contains("Unrated") { selectedPreferences.remove("Unrated") }
                else { selectedPreferences.insert("Unrated") }
            } label: {
                HStack(spacing: 7) {
                    ZStack {
                        Circle()
                            .fill(Color.gray.opacity(0.5))
                            .frame(width: 10, height: 10)
                        if unratedActive {
                            Circle()
                                .stroke(Color.gray, lineWidth: 1.5)
                                .frame(width: 15, height: 15)
                        }
                    }
                    .frame(width: 18, height: 18)
                    Text("Unrated")
                        .font(.system(size: 12, weight: .medium, design: .serif))
                        .foregroundStyle(unratedActive ? Color.white : Color.white.opacity(0.7))
                }
            }
            .buttonStyle(.plain)
            .opacity(unratedDimmed ? 0.3 : 1)

            if anyActive {
                Button("Clear") { selectedPreferences = [] }
                    .font(.system(size: 10, design: .serif))
                    .foregroundStyle(Color.white.opacity(0.4))
                    .underline()
                    .padding(.top, 2)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .background(Color(hex: "#030712").opacity(0.75))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.1), lineWidth: 1))
    }

    // MARK: - Locate Me button

    private var locateMeButton: some View {
        Button {
            if let mv = bridge.mapView, mv.userLocation.location != nil {
                bridge.center(on: mv.userLocation.coordinate)
            }
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

    // MARK: - Callout sheet

    private func restaurantCallout(_ r: Restaurant) -> some View {
        ZStack {
            Color.sunBackground.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    if let pref = r.preference {
                        Text(pref.rawValue)
                            .font(.system(size: 11, weight: .medium, design: .serif))
                            .foregroundStyle(Color(hex: pref.colorHex))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color(hex: pref.colorHex).opacity(0.12))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Color(hex: pref.colorHex).opacity(0.35), lineWidth: 1))
                    }
                    if r.beenThere {
                        Text("Visited")
                            .font(.system(size: 11, weight: .medium, design: .serif))
                            .foregroundStyle(Color.white.opacity(0.5))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.white.opacity(0.07))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1))
                    }
                    Spacer()
                }
                Text(r.name)
                    .font(.system(size: 20, weight: .bold, design: .serif))
                    .fontDesign(.serif)
                    .foregroundStyle(Color.sunText)
                let loc = [r.location, r.neighborhood].filter { !$0.isEmpty }.joined(separator: " · ")
                if !loc.isEmpty {
                    Text(loc)
                        .font(.system(.subheadline, design: .serif))
                        .foregroundStyle(Color.sunSecondary)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Geocoding

    private func geocodeAll() async {
        // Pass 1: load all cached coords synchronously — instant, no network
        var uncached: [Restaurant] = []
        for r in restaurants {
            if pins[r.id] != nil { continue }
            if let cached = UserDefaults.standard.string(forKey: Restaurant.geoKey(for: r.id)) {
                let parts = cached.split(separator: ",")
                if parts.count == 2, let lat = Double(parts[0]), let lon = Double(parts[1]) {
                    pins[r.id] = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                    continue
                }
            }
            uncached.append(r)
        }

        guard !uncached.isEmpty else { return }

        // Pass 2: geocode uncached restaurants in parallel, max 5 concurrent
        await withTaskGroup(of: (String, CLLocationCoordinate2D?).self) { group in
            var inFlight = 0
            var index = 0

            while index < uncached.count || inFlight > 0 {
                while inFlight < 5 && index < uncached.count {
                    let r = uncached[index]; index += 1; inFlight += 1
                    group.addTask {
                        let query = [r.name, r.neighborhood, r.location]
                            .filter { !$0.isEmpty }.joined(separator: " ")
                        let req = MKLocalSearch.Request()
                        req.naturalLanguageQuery = query
                        if let result = try? await MKLocalSearch(request: req).start(),
                           let coord = result.mapItems.first?.placemark.coordinate {
                            return (r.id, coord)
                        }
                        return (r.id, nil)
                    }
                }

                if let (id, coord) = await group.next() {
                    inFlight -= 1
                    if let coord {
                        UserDefaults.standard.set(
                            "\(coord.latitude),\(coord.longitude)",
                            forKey: Restaurant.geoKey(for: id)
                        )
                        await MainActor.run { pins[id] = coord }
                    }
                }
            }
        }
    }
}
