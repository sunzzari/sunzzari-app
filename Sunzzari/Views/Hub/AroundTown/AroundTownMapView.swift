import SwiftUI
import MapKit

// MARK: - Annotation

final class AroundTownAnnotation: NSObject, MKAnnotation {
    let item: AroundTownItem
    @objc dynamic var coordinate: CLLocationCoordinate2D
    var title: String? { item.name }
    var subtitle: String? { item.calloutSubtitle }

    init(item: AroundTownItem, coordinate: CLLocationCoordinate2D) {
        self.item = item
        self.coordinate = coordinate
    }
}

// MARK: - UIViewRepresentable

struct AroundTownMKMap: UIViewRepresentable {
    let annotations: [AroundTownAnnotation]
    let filterKey: String
    @Binding var selectedID: String?
    let bridge: MapBridge

    /// Fired when the callout's (i) accessory is tapped -- opens the detail sheet.
    /// Mirrors TripMKMap so both maps behave the same way.
    var onOpenDetail: ((AroundTownItem) -> Void)?

    /// Fired when a numbered bubble holds places that sit on the same spot, so
    /// zooming can never break it apart. The parent lists the members instead.
    var onOpenCluster: (([AroundTownItem]) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(selectedID: $selectedID, onOpenDetail: onOpenDetail, onOpenCluster: onOpenCluster)
    }

    static func dismantleUIView(_ uiView: MKMapView, coordinator: Coordinator) {
        coordinator.stopHeading()
    }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsUserLocation = true
        map.mapType = .standard
        map.overrideUserInterfaceStyle = .dark
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

        coordinator.onOpenDetail = onOpenDetail
        coordinator.onOpenCluster = onOpenCluster

        // Include intent state in the key so pin color refreshes after a toggle
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
        if !toAdd.isEmpty { map.addAnnotations(toAdd) }

        // Auto-fit on first load, on a filter change, and as background geocoding
        // adds pins -- but never after the user has panned or zoomed by hand.
        // The old gate required every item to be placed before fitting once, so a
        // single un-geocodable row left the map parked on its default region.
        let filterChanged = filterKey != coordinator.lastFilterKey
        let firstLoad = !coordinator.hasFittedInitially && !annotations.isEmpty
        let grew = annotations.count > coordinator.lastAnnotationCount
        if firstLoad || filterChanged || (grew && !coordinator.userHasInteracted) {
            coordinator.hasFittedInitially = true
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
        coordinator.lastAnnotationCount = annotations.count

        if let id = selectedID {
            let alreadySelected = map.selectedAnnotations.contains {
                ($0 as? AroundTownAnnotation)?.item.id == id
            }
            if !alreadySelected,
               let ann = map.annotations.first(where: { ($0 as? AroundTownAnnotation)?.item.id == id }) {
                map.selectAnnotation(ann, animated: true)
            }
        } else {
            map.selectedAnnotations
                .filter { !($0 is MKClusterAnnotation) }
                .forEach { map.deselectAnnotation($0, animated: false) }
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, MKMapViewDelegate, CLLocationManagerDelegate {
        @Binding var selectedID: String?
        var onOpenDetail: ((AroundTownItem) -> Void)?
        var onOpenCluster: (([AroundTownItem]) -> Void)?
        var isUpdating = false
        var hasFittedInitially = false
        var lastFilterKey: String = ""
        var lastAnnotationCount = 0
        var userHasInteracted = false
        private var didCenterOnUser = false

        private var headingManager: CLLocationManager?
        weak var userLocView: UserLocationAnnotationView?
        weak var mapView: MKMapView?
        private var lastDeviceHeading: CLLocationDirection = 0
        private var lastHeadingAccuracy: CLLocationDirection = 27.5

        init(
            selectedID: Binding<String?>,
            onOpenDetail: ((AroundTownItem) -> Void)? = nil,
            onOpenCluster: (([AroundTownItem]) -> Void)? = nil
        ) {
            _selectedID = selectedID
            self.onOpenDetail = onOpenDetail
            self.onOpenCluster = onOpenCluster
        }

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
                v.canShowCallout = false
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

            // Callout bubble on tap: name + one-line description, with an (i)
            // accessory that opens the full sheet. Same as the travel map.
            v.canShowCallout = true
            v.titleVisibility = .adaptive
            v.subtitleVisibility = .adaptive
            let info = UIButton(type: .detailDisclosure)
            info.tintColor = UIColor(Color.sunAccent)
            v.rightCalloutAccessoryView = info
            v.glyphImage = UIImage(systemName: ann.item.glyph)

            // Every place stays legible: tried places go grey, untried keep their
            // preference color. Nothing is faded out to near-invisible.
            if ann.item.done {
                v.markerTintColor = .systemGray
                v.alpha = 0.9
            } else {
                v.markerTintColor = UIColor(Color(hex: ann.item.markerColorHex))
                v.alpha = 1.0
            }
            v.displayPriority = ann.item.thinkingAbout ? .required : .defaultHigh
            return v
        }

        func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
            if !animated && hasFittedInitially { userHasInteracted = true }
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) { updateCone() }
        func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) { updateCone() }

        func mapView(_ mapView: MKMapView,
                     annotationView view: MKAnnotationView,
                     calloutAccessoryControlTapped control: UIControl) {
            if let ann = view.annotation as? AroundTownAnnotation {
                onOpenDetail?(ann.item)
            }
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            // Numbered bubble tap -> zoom into the cluster's member bounds so it
            // breaks apart. MapKit does nothing here by default, which is why
            // tapping a numbered pin used to be a dead end.
            if let cluster = view.annotation as? MKClusterAnnotation {
                let coords = cluster.memberAnnotations.map(\.coordinate)
                guard !coords.isEmpty else { return }

                // Places on the SAME spot can never be split by zooming, and 24
                // sets of them exist in the real data (two rows for Camphor, the
                // three ABSteak rows, Damian and Bread Lounge in one building).
                // Zooming those forever was the original dead end in a new form,
                // so the member list opens instead.
                let anchor = CLLocation(latitude: coords[0].latitude, longitude: coords[0].longitude)
                let spread = coords.map {
                    anchor.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude))
                }.max() ?? 0
                if spread < 30 {
                    let items = cluster.memberAnnotations.compactMap { ($0 as? AroundTownAnnotation)?.item }
                    mapView.deselectAnnotation(cluster, animated: false)
                    if !items.isEmpty { onOpenCluster?(items) }
                    return
                }

                var rect = MKMapRect.null
                for c in coords {
                    let p = MKMapPoint(c)
                    rect = rect.union(MKMapRect(x: p.x, y: p.y, width: 0, height: 0))
                }
                let dx = max(rect.size.width * 0.5, 200)
                let dy = max(rect.size.height * 0.5, 200)
                mapView.setVisibleMapRect(rect.insetBy(dx: -dx, dy: -dy), animated: true)
                mapView.deselectAnnotation(cluster, animated: false)
                return
            }

            UIView.animate(withDuration: 0.18) {
                view.transform = CGAffineTransform(scaleX: 1.18, y: 1.18)
            }
            view.layer.shadowColor = UIColor(Color.sunAccent).cgColor
            view.layer.shadowRadius = 8
            view.layer.shadowOpacity = 0.7
            view.layer.shadowOffset = .zero

            guard !isUpdating else { return }
            if let ann = view.annotation as? AroundTownAnnotation { selectedID = ann.item.id }
        }

        func mapView(_ mapView: MKMapView, didDeselect view: MKAnnotationView) {
            UIView.animate(withDuration: 0.18) { view.transform = .identity }
            view.layer.shadowOpacity = 0

            guard !isUpdating else { return }
            if view.annotation is MKClusterAnnotation { return }
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
    // ONE sheet, selected by case. Two separate .sheet modifiers on the same
    // view silently conflict -- the cluster sheet never presented until these
    // were merged.
    private enum ActiveSheet: Identifiable {
        case detail(String)
        case cluster([AroundTownItem])

        var id: String {
            switch self {
            case .detail(let itemID): return "detail-\(itemID)"
            case .cluster(let members): return "cluster-" + members.map(\.id).joined(separator: "-")
            }
        }
    }

    @State private var activeSheet: ActiveSheet?
    @State private var bridge = MapBridge()
    @State private var geocodePassComplete = false

    /// The primary toggle: everything, or only the places we have not been to yet.
    enum TriedFilter: String, CaseIterable {
        case all = "Around Town"
        case notTried = "Haven't Tried"
    }

    @State private var triedFilter: TriedFilter = .all
    @State private var filterRegion: AroundTownItem.Region? = nil
    @State private var filterKind: AroundTownItem.Kind? = nil
    @State private var wantToTryOnly = false

    private var hasActiveFilters: Bool {
        filterRegion != nil || filterKind != nil || wantToTryOnly || triedFilter != .all
    }

    private var filtered: [AroundTownItem] {
        items.filter { item in
            let regionOK = filterRegion == nil || item.region == filterRegion
            let kindOK   = filterKind == nil || item.kind == filterKind
            let triedOK  = triedFilter == .all || !item.done
            let wantOK   = !wantToTryOnly || item.thinkingAbout
            return regionOK && kindOK && triedOK && wantOK
        }
    }

    private var annotations: [AroundTownAnnotation] {
        filtered.compactMap { item in
            pins[item.id].map { AroundTownAnnotation(item: item, coordinate: $0) }
        }
    }

    private var filterKey: String {
        let kindStr = filterKind.map { $0 == .restaurant ? "rest" : "act" } ?? "all"
        return "\(filterRegion?.label ?? "all")|\(kindStr)|\(triedFilter.rawValue)|\(wantToTryOnly)"
    }

    var body: some View {
        ZStack {
            AroundTownMKMap(
                annotations: annotations,
                filterKey: filterKey,
                selectedID: $selectedID,
                bridge: bridge,
                onOpenDetail: { activeSheet = .detail($0.id) },
                onOpenCluster: { activeSheet = .cluster($0) }
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
                    locateMeButton
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
                clusterSheet(members)
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
            }
        }
        .task(id: items.count) { await geocodeAll() }
    }

    // MARK: - Controls

    private var controlBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                ForEach(TriedFilter.allCases, id: \.self) { option in
                    Button { triedFilter = option } label: {
                        Text(option.rawValue)
                            .font(.system(size: 13, weight: .semibold, design: .serif))
                            .foregroundStyle(triedFilter == option ? Color.sunBackground : Color.white.opacity(0.75))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(triedFilter == option ? Color.sunAccent : Color.white.opacity(0.08))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(
                                triedFilter == option ? Color.sunAccent : Color.white.opacity(0.2),
                                lineWidth: 1
                            ))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)

            HStack(spacing: 6) {
                Text("\(annotations.count) on the map")
                    .font(.system(size: 11, design: .serif))
                    .foregroundStyle(Color.white.opacity(0.45))
                if filtered.count > annotations.count {
                    // Once the pass is done the remainder is not "still loading" --
                    // those rows have no address the geocoder can place.
                    Text(geocodePassComplete
                         ? "· \(filtered.count - annotations.count) with no map location"
                         : "· \(filtered.count - annotations.count) still locating")
                        .font(.system(size: 11, design: .serif))
                        .foregroundStyle(Color.white.opacity(0.3))
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

                    if hasActiveFilters {
                        Button {
                            filterRegion = nil
                            filterKind = nil
                            wantToTryOnly = false
                            triedFilter = .all
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

    // MARK: - Cluster member list

    /// Shown when a numbered bubble holds places at the same address, where no
    /// amount of zooming will separate them. Picking one opens its description.
    @ViewBuilder
    private func clusterSheet(_ members: [AroundTownItem]) -> some View {
        ZStack {
            Color.sunBackground.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                Text("\(members.count) places here")
                    .font(.system(size: 18, weight: .bold, design: .serif))
                    .foregroundStyle(Color.sunText)
                    .padding(.horizontal, 20)
                    .padding(.top, 22)
                    .padding(.bottom, 12)

                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(members) { member in
                            Button {
                                activeSheet = .detail(member.id)
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
                                    Image(systemName: "chevron.right")
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

    // MARK: - Geocoding

    /// Accepts a coordinate only if it lands in LA or the SF Bay Area, and uses it
    /// to set the item's region -- the coordinate is a better region signal than
    /// the Notion text, which says "LA / SF" for a few places.
    private func accept(id: String, coord: CLLocationCoordinate2D) {
        guard let region = AroundTownItem.Region.from(coordinate: coord) else { return }
        pins[id] = coord
        if let idx = items.firstIndex(where: { $0.id == id }) {
            items[idx].region = region
            items[idx].coordinate = coord
        }
    }

    private static let failPrefix = "FAIL:"
    private static let failRetryInterval: TimeInterval = 7 * 24 * 60 * 60

    private static func cachedCoord(forKey key: String) -> CLLocationCoordinate2D? {
        guard let cached = UserDefaults.standard.string(forKey: key),
              !cached.hasPrefix(failPrefix) else { return nil }
        let parts = cached.split(separator: ",")
        guard parts.count == 2, let lat = Double(parts[0]), let lon = Double(parts[1]) else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    /// True when a lookup for this item failed recently, so it is not retried on
    /// every single launch.
    private static func failedRecently(_ id: String, now: TimeInterval) -> Bool {
        guard let cached = UserDefaults.standard.string(forKey: AroundTownItem.geoKey(for: id)),
              cached.hasPrefix(failPrefix),
              let stamp = TimeInterval(cached.dropFirst(failPrefix.count)) else { return false }
        return now - stamp < failRetryInterval
    }

    private func geocodeAll() async {
        defer { geocodePassComplete = true }
        let now = Date().timeIntervalSince1970
        var uncached: [AroundTownItem] = []
        for item in items {
            if pins[item.id] != nil { continue }
            // The Restaurants map's cache is a valid source: same Notion page IDs.
            // A fresh lookup below writes both keys, so the two maps share work.
            let coord = Self.cachedCoord(forKey: AroundTownItem.geoKey(for: item.id))
                ?? (item.kind == .restaurant
                    ? Self.cachedCoord(forKey: Restaurant.geoKey(for: item.id))
                    : nil)
            if let coord {
                accept(id: item.id, coord: coord)
                continue
            }
            if Self.failedRecently(item.id, now: now) { continue }
            uncached.append(item)
        }

        guard !uncached.isEmpty else { return }

        // A name the geocoder cannot place resolves to the bare metro centroid
        // (an activity row like "Sushi making" is not a venue). Those centroids
        // are looked up once and any match on one is rejected rather than dropped
        // on the map as a pin at city hall.
        var centroids: [CLLocationCoordinate2D] = []
        for hint in Set(uncached.map(\.geoCityFallback)) {
            if let c = await PlaceGeocoder.coordinate(venue: "", city: hint) { centroids.append(c) }
        }
        func isCentroid(_ c: CLLocationCoordinate2D) -> Bool {
            let loc = CLLocation(latitude: c.latitude, longitude: c.longitude)
            return centroids.contains {
                loc.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude)) < 150
            }
        }

        await withTaskGroup(of: (String, Bool, CLLocationCoordinate2D?).self) { group in
            var inFlight = 0
            var index = 0

            while index < uncached.count || inFlight > 0 {
                while inFlight < 8 && index < uncached.count {
                    let item = uncached[index]; index += 1; inFlight += 1
                    group.addTask {
                        var coord = await PlaceGeocoder.coordinate(venue: item.geoVenue, city: item.geoCity)
                        if coord == nil {
                            coord = await PlaceGeocoder.coordinate(
                                venue: item.geoVenue, city: item.geoCityFallback
                            )
                        }
                        return (item.id, item.kind == .restaurant, coord)
                    }
                }

                if let (id, isRestaurant, coord) = await group.next() {
                    inFlight -= 1
                    let usable = coord.flatMap { c -> CLLocationCoordinate2D? in
                        guard AroundTownItem.Region.from(coordinate: c) != nil, !isCentroid(c) else { return nil }
                        return c
                    }
                    if let usable {
                        let value = "\(usable.latitude),\(usable.longitude)"
                        UserDefaults.standard.set(value, forKey: AroundTownItem.geoKey(for: id))
                        if isRestaurant, UserDefaults.standard.string(forKey: Restaurant.geoKey(for: id)) == nil {
                            UserDefaults.standard.set(value, forKey: Restaurant.geoKey(for: id))
                        }
                        await MainActor.run { accept(id: id, coord: usable) }
                    } else {
                        UserDefaults.standard.set(
                            "\(Self.failPrefix)\(now)",
                            forKey: AroundTownItem.geoKey(for: id)
                        )
                    }
                }
            }
        }
    }
}
