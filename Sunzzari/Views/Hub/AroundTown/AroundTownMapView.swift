import SwiftUI
import MapKit

// MARK: - Annotation

final class AroundTownAnnotation: NSObject, MKAnnotation {
    let item: AroundTownItem
    @objc dynamic var coordinate: CLLocationCoordinate2D
    var title: String? { item.name }

    init(item: AroundTownItem, coordinate: CLLocationCoordinate2D) {
        self.item = item
        self.coordinate = coordinate
    }
}

// MARK: - UIViewRepresentable

struct AroundTownMKMap: UIViewRepresentable {
    let annotations: [AroundTownAnnotation]
    let totalCount: Int
    let filterKey: String
    @Binding var selectedID: String?
    let bridge: MapBridge

    func makeCoordinator() -> Coordinator { Coordinator(selectedID: $selectedID) }

    static func dismantleUIView(_ uiView: MKMapView, coordinator: Coordinator) {
        coordinator.stopHeading()
    }

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
        map.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: "aroundtown")
        map.register(
            MKMarkerAnnotationView.self,
            forAnnotationViewWithReuseIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier
        )
        bridge.mapView = map
        context.coordinator.mapView = map
        context.coordinator.startHeading()
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.isUpdating = true
        defer { coordinator.isUpdating = false }

        // Include intent state in key so pin color refreshes after toggle
        func key(for ann: AroundTownAnnotation) -> String {
            "\(ann.item.id)|\(ann.item.thinkingAbout)|\(ann.item.done)"
        }

        let existing = Set(map.annotations.compactMap { ($0 as? AroundTownAnnotation).map(key) })
        let desired  = Set(annotations.map(key))

        let toRemove = map.annotations.filter {
            guard let a = $0 as? AroundTownAnnotation else { return false }
            return !desired.contains(key(for: a))
        }
        if !toRemove.isEmpty { map.removeAnnotations(toRemove) }

        let toAdd = annotations.filter { !existing.contains(key(for: $0)) }
        if !toAdd.isEmpty {
            map.addAnnotations(toAdd)
            let placed = map.annotations.filter { $0 is AroundTownAnnotation }.count
            if !coordinator.didFitAll && totalCount > 0 && placed >= totalCount {
                coordinator.didFitAll = true
                coordinator.lastFilterKey = filterKey
                let anns = map.annotations.filter { !($0 is MKUserLocation) }
                DispatchQueue.main.async { map.showAnnotations(anns, animated: true) }
            }
        }

        if coordinator.didFitAll && filterKey != coordinator.lastFilterKey {
            coordinator.lastFilterKey = filterKey
            DispatchQueue.main.async {
                let anns = map.annotations.filter { !($0 is MKUserLocation) }
                if !anns.isEmpty {
                    map.showAnnotations(anns, animated: true)
                } else {
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

        if let id = selectedID {
            let alreadySelected = map.selectedAnnotations.contains {
                ($0 as? AroundTownAnnotation)?.item.id == id
            }
            if !alreadySelected,
               let ann = map.annotations.first(where: { ($0 as? AroundTownAnnotation)?.item.id == id }) {
                map.selectAnnotation(ann, animated: true)
            }
        } else {
            map.selectedAnnotations.forEach { map.deselectAnnotation($0, animated: false) }
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, MKMapViewDelegate, CLLocationManagerDelegate {
        @Binding var selectedID: String?
        var isUpdating = false
        var didFitAll = false
        var lastFilterKey: String = ""
        private var didCenterOnUser = false

        private var headingManager: CLLocationManager?
        weak var userLocView: UserLocationAnnotationView?
        weak var mapView: MKMapView?
        private var lastDeviceHeading: CLLocationDirection = 0
        private var lastHeadingAccuracy: CLLocationDirection = 27.5

        init(selectedID: Binding<String?>) { _selectedID = selectedID }

        func startHeading() {
            guard CLLocationManager.headingAvailable() else { return }
            let mgr = CLLocationManager()
            mgr.delegate = self
            mgr.headingFilter = 3
            mgr.startUpdatingHeading()
            headingManager = mgr
        }

        func stopHeading() {
            headingManager?.stopUpdatingHeading()
            headingManager = nil
        }

        private func updateCone() {
            let mapRotation = mapView?.camera.heading ?? 0
            userLocView?.setHeading(lastDeviceHeading - mapRotation, accuracy: lastHeadingAccuracy)
        }

        func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
            guard newHeading.headingAccuracy >= 0 else { return }
            lastDeviceHeading = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
            lastHeadingAccuracy = newHeading.headingAccuracy
            updateCone()
        }

        func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool { true }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation {
                let v = UserLocationAnnotationView(
                    annotation: annotation,
                    reuseIdentifier: UserLocationAnnotationView.reuseID
                )
                userLocView = v
                return v
            }

            if let cluster = annotation as? MKClusterAnnotation {
                let v = mapView.dequeueReusableAnnotationView(
                    withIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier,
                    for: cluster
                ) as? MKMarkerAnnotationView
                    ?? MKMarkerAnnotationView(annotation: cluster, reuseIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier)
                v.markerTintColor = UIColor(red: 0.984, green: 0.749, blue: 0.141, alpha: 1)
                v.glyphText = "\(cluster.memberAnnotations.count)"
                v.titleVisibility = .hidden
                v.subtitleVisibility = .hidden
                return v
            }

            guard let ann = annotation as? AroundTownAnnotation else { return nil }
            let v = mapView.dequeueReusableAnnotationView(
                withIdentifier: "aroundtown", for: annotation
            ) as? MKMarkerAnnotationView
                ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: "aroundtown")
            v.clusteringIdentifier = "aroundtown"
            v.canShowCallout = false
            v.titleVisibility = .hidden
            v.subtitleVisibility = .hidden
            v.glyphImage = UIImage(systemName: ann.item.glyph)

            if ann.item.thinkingAbout {
                v.markerTintColor = UIColor(Color(hex: ann.item.markerColorHex))
                v.alpha = 1.0
            } else if ann.item.done {
                v.markerTintColor = .systemGray3
                v.alpha = 0.65
            } else {
                v.markerTintColor = UIColor(Color(hex: ann.item.markerColorHex)).withAlphaComponent(0.45)
                v.alpha = 0.8
            }
            return v
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) { updateCone() }
        func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) { updateCone() }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            guard !isUpdating else { return }
            if let ann = view.annotation as? AroundTownAnnotation { selectedID = ann.item.id }
        }

        func mapView(_ mapView: MKMapView, didDeselect view: MKAnnotationView) {
            guard !isUpdating else { return }
            selectedID = nil
        }

        func mapView(_ mapView: MKMapView, didUpdate userLocation: MKUserLocation) {
            guard !didCenterOnUser else { return }
            guard !mapView.annotations.contains(where: { $0 is AroundTownAnnotation }) else { return }
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

// MARK: - AroundTownMapView

struct AroundTownMapView: View {
    @Binding var items: [AroundTownItem]

    @State private var pins: [String: CLLocationCoordinate2D] = [:]
    @State private var selectedID: String?
    @State private var bridge = MapBridge()

    enum IntentFilter { case thinkingAbout, done }

    @State private var filterRegion: AroundTownItem.Region? = nil
    @State private var filterKind: AroundTownItem.Kind? = nil
    @State private var filterIntent: IntentFilter? = nil

    private var hasActiveFilters: Bool {
        filterRegion != nil || filterKind != nil || filterIntent != nil
    }

    private var filtered: [AroundTownItem] {
        items.filter { item in
            let regionOK = filterRegion == nil || item.region == filterRegion
            let kindOK   = filterKind == nil || item.kind == filterKind
            let intentOK: Bool
            switch filterIntent {
            case .thinkingAbout: intentOK = item.thinkingAbout
            case .done:          intentOK = item.done
            case nil:            intentOK = true
            }
            return regionOK && kindOK && intentOK
        }
    }

    private var annotations: [AroundTownAnnotation] {
        pins.compactMap { id, coord in
            filtered.first { $0.id == id }.map { AroundTownAnnotation(item: $0, coordinate: coord) }
        }
    }

    private var filterKey: String {
        let intentStr: String
        switch filterIntent {
        case .thinkingAbout: intentStr = "thinking"
        case .done:          intentStr = "done"
        case nil:            intentStr = "all"
        }
        return "\(filterRegion?.label ?? "all")|\(filterKind.map { "\($0)" } ?? "all")|\(intentStr)"
    }

    var body: some View {
        ZStack {
            AroundTownMKMap(
                annotations: annotations,
                totalCount: filtered.count,
                filterKey: filterKey,
                selectedID: $selectedID,
                bridge: bridge
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                filterBar
                Spacer()
            }

            VStack {
                Spacer()
                HStack(alignment: .bottom, spacing: 0) {
                    kindLegend
                        .padding(.leading, 16)
                    Spacer()
                    locateMeButton
                        .padding(.trailing, 16)
                }
                .padding(.bottom, 32)
            }
        }
        .navigationTitle("Around Town")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(
            isPresented: Binding(
                get: { selectedID != nil },
                set: { if !$0 { selectedID = nil } }
            )
        ) {
            if let id = selectedID, let idx = items.firstIndex(where: { $0.id == id }) {
                calloutSheet(binding: $items[idx])
                    .presentationDetents([.fraction(0.42)])
                    .presentationDragIndicator(.visible)
            }
        }
        .task { await geocodeAll() }
    }

    // MARK: - Filter bar

    private var filterBar: some View {
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

                filterChip(label: "Want to Try", icon: "bookmark", isActive: filterIntent == .thinkingAbout) {
                    filterIntent = filterIntent == .thinkingAbout ? nil : .thinkingAbout
                }
                filterChip(label: "Done", icon: "checkmark.circle", isActive: filterIntent == .done) {
                    filterIntent = filterIntent == .done ? nil : .done
                }

                if hasActiveFilters {
                    Button {
                        filterRegion = nil
                        filterKind = nil
                        filterIntent = nil
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

    // MARK: - Kind legend (bottom-left)

    private var kindLegend: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Circle()
                    .fill(Color(hex: "#54A0FF"))
                    .frame(width: 10, height: 10)
                Text("Restaurant")
                    .font(.system(size: 12, weight: .medium, design: .serif))
                    .foregroundStyle(Color.white.opacity(0.75))
            }
            HStack(spacing: 7) {
                Circle()
                    .fill(Color(hex: "#A78BFA"))
                    .frame(width: 10, height: 10)
                Text("Activity")
                    .font(.system(size: 12, weight: .medium, design: .serif))
                    .foregroundStyle(Color.white.opacity(0.75))
            }
            HStack(spacing: 7) {
                Circle()
                    .fill(Color.gray.opacity(0.4))
                    .frame(width: 10, height: 10)
                Text("Done")
                    .font(.system(size: 12, weight: .medium, design: .serif))
                    .foregroundStyle(Color.white.opacity(0.45))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .background(Color(hex: "#030712").opacity(0.75))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.1), lineWidth: 1))
    }

    // MARK: - Locate Me

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

    @ViewBuilder
    private func calloutSheet(binding: Binding<AroundTownItem>) -> some View {
        let item = binding.wrappedValue
        ZStack {
            Color.sunBackground.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 14) {
                // Kind + region badges
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
                    Spacer()
                }

                Text(item.name)
                    .font(.system(size: 20, weight: .bold, design: .serif))
                    .fontDesign(.serif)
                    .foregroundStyle(Color.sunText)

                if !item.subtitle.isEmpty {
                    Text(item.subtitle)
                        .font(.system(.subheadline, design: .serif))
                        .foregroundStyle(Color.sunSecondary)
                }

                Divider()
                    .background(Color.white.opacity(0.1))

                // Intent toggles
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
                        label: "Done",
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

    // MARK: - Geocoding

    private func geocodeAll() async {
        var uncached: [AroundTownItem] = []
        for item in items {
            if pins[item.id] != nil { continue }
            if let cached = UserDefaults.standard.string(forKey: AroundTownItem.geoKey(for: item.id)) {
                let parts = cached.split(separator: ",")
                if parts.count == 2, let lat = Double(parts[0]), let lon = Double(parts[1]) {
                    pins[item.id] = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                    continue
                }
            }
            uncached.append(item)
        }

        guard !uncached.isEmpty else { return }

        await withTaskGroup(of: (String, CLLocationCoordinate2D?).self) { group in
            var inFlight = 0
            var index = 0

            while index < uncached.count || inFlight > 0 {
                while inFlight < 5 && index < uncached.count {
                    let item = uncached[index]; index += 1; inFlight += 1
                    group.addTask {
                        let query = [item.name, item.subtitle].filter { !$0.isEmpty }.joined(separator: " ")
                        let req = MKLocalSearch.Request()
                        req.naturalLanguageQuery = query
                        if let result = try? await MKLocalSearch(request: req).start(),
                           let coord = result.mapItems.first?.placemark.coordinate {
                            return (item.id, coord)
                        }
                        return (item.id, nil)
                    }
                }

                if let (id, coord) = await group.next() {
                    inFlight -= 1
                    if let coord {
                        UserDefaults.standard.set(
                            "\(coord.latitude),\(coord.longitude)",
                            forKey: AroundTownItem.geoKey(for: id)
                        )
                        await MainActor.run { pins[id] = coord }
                    }
                }
            }
        }
    }
}
