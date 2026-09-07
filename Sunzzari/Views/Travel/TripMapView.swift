import SwiftUI
import MapKit

// MARK: - Bridge (SwiftUI -> UIKit imperative calls)

final class TripMapBridge {
    weak var mapView: MKMapView?

    /// Default: fit only item annotations, ignoring the user-location dot.
    /// Pass includeUser=true (Near Me active) to keep the user dot in frame.
    func fitAll(animated: Bool = true, includeUser: Bool = false) {
        guard let mv = mapView else { return }
        let anns: [MKAnnotation] = includeUser
            ? mv.annotations
            : mv.annotations.filter { !($0 is MKUserLocation) }
        let withoutUser = anns.filter { !($0 is MKUserLocation) }
        guard !withoutUser.isEmpty else { return }
        mv.showAnnotations(anns, animated: animated)
    }

    func panTo(_ coord: CLLocationCoordinate2D, zoom: CLLocationDistance = 2000) {
        guard let mv = mapView else { return }
        mv.setRegion(
            MKCoordinateRegion(center: coord, latitudinalMeters: zoom, longitudinalMeters: zoom),
            animated: true
        )
    }

    func centerOnUser() {
        guard let mv = mapView, let loc = mv.userLocation.location else { return }
        panTo(loc.coordinate, zoom: 4000)
    }

    /// Fits the map to the annotations whose item IDs are in `ids`.
    /// Falls back to fitAll if no matching annotations are found.
    func fitToIDs(_ ids: Set<String>, in items: [TripItem]) {
        guard let mv = mapView else { return }
        let coords = items
            .filter { ids.contains($0.id) }
            .compactMap { item -> CLLocationCoordinate2D? in
                guard let lat = item.latitude, let lon = item.longitude else { return nil }
                return CLLocationCoordinate2D(latitude: lat, longitude: lon)
            }
        guard !coords.isEmpty else {
            fitAll()
            return
        }
        if coords.count == 1 {
            panTo(coords[0], zoom: 2000)
            return
        }
        var rect = MKMapRect.null
        for c in coords {
            let p = MKMapPoint(c)
            rect = rect.union(MKMapRect(x: p.x, y: p.y, width: 0, height: 0))
        }
        let dx = max(rect.size.width * 0.4, 500)
        let dy = max(rect.size.height * 0.4, 500)
        mv.setVisibleMapRect(rect.insetBy(dx: -dx, dy: -dy), animated: true)
    }

    /// Selects the annotation with the given trip item ID after a short delay so
    /// the pan animation can finish and clusters have a chance to dissolve.
    /// Must be called AFTER panTo so the zoom level is already set.
    func selectPin(id: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
            guard let mv = self?.mapView,
                  let ann = mv.annotations.first(where: { ($0 as? TripItemAnnotation)?.item.id == id })
            else { return }
            mv.selectAnnotation(ann, animated: true)
        }
    }
}

// MARK: - UIViewRepresentable

struct TripMKMap: UIViewRepresentable {
    let annotations: [TripItemAnnotation]
    let filterKey: String
    @Binding var selectedID: String?
    let bridge: TripMapBridge

    var interactive: Bool = true

    // When true, auto-fits include the user-location annotation so the user
    // dot stays in frame. Used when Near Me is active on the parent view.
    var fitIncludesUser: Bool = false

    // Fired when the callout's (i) info accessory is tapped. Parent uses this
    // to open ItemDetailSheet, mirroring the second-tap behavior on rows.
    var onOpenDetail: ((TripItem) -> Void)?

    // Fired when a tapped cluster CANNOT be split by zooming, because its
    // members sit on the same coordinate. Parent shows a picker instead.
    var onOpenCluster: (([TripItem]) -> Void)?

    // Item IDs returned by the AI assistant — rendered in a distinct blue tint.
    var highlightedItemIds: Set<String> = []

    func makeCoordinator() -> Coordinator {
        Coordinator(selectedID: $selectedID, onOpenDetail: onOpenDetail, onOpenCluster: onOpenCluster)
    }

    static func dismantleUIView(_ uiView: MKMapView, coordinator: Coordinator) {
        coordinator.stopHeading()
    }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsUserLocation = interactive
        map.mapType = .standard
        map.overrideUserInterfaceStyle = .dark
        map.isZoomEnabled = interactive
        map.isScrollEnabled = interactive
        map.isPitchEnabled = interactive
        map.isRotateEnabled = interactive
        map.isUserInteractionEnabled = interactive
        // Default to world view, will fit to pins when they load
        map.setRegion(
            MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 40, longitude: 10),
                latitudinalMeters: 5_000_000, longitudinalMeters: 5_000_000
            ),
            animated: false
        )
        map.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: "tripItem")
        map.register(
            MKMarkerAnnotationView.self,
            forAnnotationViewWithReuseIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier
        )
        bridge.mapView = map
        context.coordinator.mapView = map
        if interactive { context.coordinator.startHeading() }
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.isUpdating = true
        defer { coordinator.isUpdating = false }

        // Refresh callout-accessory callback so it always points to the
        // latest closure captured by the SwiftUI body.
        coordinator.onOpenDetail = onOpenDetail

        // Sync annotations
        let existing = Set(map.annotations.compactMap { ($0 as? TripItemAnnotation)?.item.id })
        let desired = Set(annotations.map(\.item.id))

        let toRemove = map.annotations.filter {
            guard let ta = $0 as? TripItemAnnotation else { return false }
            return !desired.contains(ta.item.id)
        }
        if !toRemove.isEmpty { map.removeAnnotations(toRemove) }

        let toAdd = annotations.filter { !existing.contains($0.item.id) }
        if !toAdd.isEmpty {
            map.addAnnotations(toAdd)
        }

        // Re-fit when filter changes, on first load, OR when annotations grow
        // AND the user hasn't manually panned/zoomed yet. The user-interaction
        // flag is set in regionWillChangeAnimated when animated=false (gesture-
        // driven). Programmatic showAnnotations(animated: true) doesn't trip it.
        // This handles the cached-hotel-only -> background-geocoded-rest case
        // for ANY initial cached count, without yanking the user's manual zoom.
        let filterChanged = filterKey != coordinator.lastFilterKey
        let firstLoad = !coordinator.hasFittedInitially && !annotations.isEmpty
        let annotationsGrew = annotations.count > coordinator.lastAnnotationCount
        if firstLoad || filterChanged || (annotationsGrew && !coordinator.userHasInteracted) {
            coordinator.hasFittedInitially = true
            coordinator.lastFilterKey = filterKey
            let includeUser = fitIncludesUser
            DispatchQueue.main.async {
                let itemAnns = map.annotations.filter { !($0 is MKUserLocation) }
                guard !itemAnns.isEmpty else { return }
                let anns: [MKAnnotation] = includeUser ? map.annotations : itemAnns
                map.showAnnotations(anns, animated: true)
            }
        }
        coordinator.lastAnnotationCount = annotations.count

        // Sync highlight and selection state on visible annotation views.
        coordinator.highlightedItemIds = highlightedItemIds
        for ann in map.annotations {
            guard let ta = ann as? TripItemAnnotation,
                  let view = map.view(for: ann) as? MKMarkerAnnotationView else {
                continue
            }
            let isSelected = ta.item.id == selectedID
            view.displayPriority = isSelected ? .required : .defaultHigh
            if highlightedItemIds.contains(ta.item.id) {
                view.markerTintColor = UIColor(red: 0.231, green: 0.510, blue: 0.965, alpha: 1)
            } else {
                let status = ta.item.status ?? .researching
                view.markerTintColor = UIColor(Color(hex: status.colorHex))
            }
        }

        if let id = selectedID {
            let alreadySelected = map.selectedAnnotations.contains {
                ($0 as? TripItemAnnotation)?.item.id == id
            }
            if !alreadySelected,
               let ann = map.annotations.first(where: { ($0 as? TripItemAnnotation)?.item.id == id }) {
                map.selectAnnotation(ann, animated: true)
            }
        } else {
            map.selectedAnnotations.forEach { map.deselectAnnotation($0, animated: false) }
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, MKMapViewDelegate, CLLocationManagerDelegate {
        @Binding var selectedID: String?
        var onOpenDetail: ((TripItem) -> Void)?
        var onOpenCluster: (([TripItem]) -> Void)?
        var isUpdating = false
        var hasFittedInitially = false
        var lastFilterKey: String = ""
        var lastAnnotationCount = 0
        var userHasInteracted = false
        var highlightedItemIds: Set<String> = []

        private var headingManager: CLLocationManager?
        weak var userLocView: UserLocationAnnotationView?
        weak var mapView: MKMapView?
        private var lastDeviceHeading: CLLocationDirection = 0
        private var lastHeadingAccuracy: CLLocationDirection = 27.5

        init(
            selectedID: Binding<String?>,
            onOpenDetail: ((TripItem) -> Void)? = nil,
            onOpenCluster: (([TripItem]) -> Void)? = nil
        ) {
            _selectedID = selectedID
            self.onOpenDetail = onOpenDetail
            self.onOpenCluster = onOpenCluster
        }

        /// Members closer together than this can never be visually separated,
        /// so MapKit re-clusters them at every zoom level.
        private static let coincidentThresholdMeters: CLLocationDistance = 30

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

        // Cone angle = device heading corrected for map rotation.
        // Without this, manually rotating the map makes the cone point
        // in the wrong screen direction relative to map features.
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

        func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool {
            return true
        }

        func mapView(_ mapView: MKMapView,
                     annotationView view: MKAnnotationView,
                     calloutAccessoryControlTapped control: UIControl) {
            if let ta = view.annotation as? TripItemAnnotation {
                onOpenDetail?(ta.item)
            }
        }

        // animated=false typically means a user gesture; programmatic
        // setRegion / showAnnotations call with animated=true. The initial
        // setRegion(animated: false) in makeUIView also fires this delegate
        // before any user input, so we gate on hasFittedInitially: we only
        // treat a region change as user interaction AFTER we've completed at
        // least one programmatic auto-fit. Otherwise the first setRegion
        // would lock out subsequent fits as background-geocoded pins arrive.
        func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
            if !animated && hasFittedInitially { userHasInteracted = true }
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            updateCone()
        }

        func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
            updateCone()
        }

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
                ) as? MKMarkerAnnotationView ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier)
                v.markerTintColor = UIColor(red: 0.984, green: 0.749, blue: 0.141, alpha: 1) // sunAccent
                v.glyphText = "\(cluster.memberAnnotations.count)"
                v.titleVisibility = .hidden
                v.subtitleVisibility = .hidden
                return v
            }

            guard let ta = annotation as? TripItemAnnotation else { return nil }
            let v = mapView.dequeueReusableAnnotationView(
                withIdentifier: "tripItem",
                for: annotation
            ) as? MKMarkerAnnotationView ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: "tripItem")
            v.clusteringIdentifier = "tripItem"
            // Show MapKit's built-in callout bubble on tap, mirroring the web
            // app's InfoWindow. Title comes from annotation.title (item name);
            // subtitle is type + legCity + status. The right accessory is an
            // info button that the parent treats as a "open detail" intent.
            v.canShowCallout = true
            v.titleVisibility = .adaptive
            v.subtitleVisibility = .adaptive
            let info = UIButton(type: .detailDisclosure)
            info.tintColor = UIColor(Color.sunAccent)
            v.rightCalloutAccessoryView = info

            // Color = AI-highlighted (blue) > STATUS color. Glyph = TYPE.
            if self.highlightedItemIds.contains(ta.item.id) {
                v.markerTintColor = UIColor(red: 0.231, green: 0.510, blue: 0.965, alpha: 1)
            } else {
                let status = ta.item.status ?? .researching
                v.markerTintColor = UIColor(Color(hex: status.colorHex))
            }

            let type = ta.item.type ?? .other
            v.glyphImage = UIImage(systemName: type.sfSymbol)

            // Selected state: larger display priority
            let isSelected = ta.item.id == selectedID
            v.displayPriority = isSelected ? .required : .defaultHigh

            return v
        }

        /// Greatest distance between any two members, in meters.
        private func spreadMeters(_ coords: [CLLocationCoordinate2D]) -> CLLocationDistance {
            guard coords.count > 1 else { return 0 }
            var maxDistance: CLLocationDistance = 0
            for i in 0..<coords.count {
                for j in (i + 1)..<coords.count {
                    let a = CLLocation(latitude: coords[i].latitude, longitude: coords[i].longitude)
                    let b = CLLocation(latitude: coords[j].latitude, longitude: coords[j].longitude)
                    maxDistance = max(maxDistance, a.distance(from: b))
                }
            }
            return maxDistance
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            // Cluster tap → zoom into the cluster's member bounds. MapKit's
            // default behavior on a cluster annotation tap is to do nothing,
            // which leaves the user stuck. Match elisa-travel-map's Google
            // MarkerClusterer behavior: tap = zoom in until cluster splits.
            if let cluster = view.annotation as? MKClusterAnnotation {
                let coords = cluster.memberAnnotations.map(\.coordinate)
                guard !coords.isEmpty else { return }

                // Coincident members can NEVER be split by zooming - MapKit
                // re-clusters them at every level, so the old zoom was a dead
                // end you could not escape. This is the common case, not an
                // edge case: six Park City items share the "Montage Deer
                // Valley" geocode and three share "Main Street". Hand them to
                // the parent as a list instead.
                if let onOpenCluster, spreadMeters(coords) < Self.coincidentThresholdMeters {
                    let items = cluster.memberAnnotations.compactMap { ($0 as? TripItemAnnotation)?.item }
                    if !items.isEmpty {
                        mapView.deselectAnnotation(cluster, animated: false)
                        onOpenCluster(items)
                        return
                    }
                }

                var rect = MKMapRect.null
                for c in coords {
                    let p = MKMapPoint(c)
                    rect = rect.union(MKMapRect(x: p.x, y: p.y, width: 0, height: 0))
                }
                let padded: MKMapRect
                if rect.size.width == 0 && rect.size.height == 0 {
                    // Single coordinate: zoom in directly.
                    let point = MKMapPoint(coords[0])
                    padded = MKMapRect(x: point.x - 500, y: point.y - 500, width: 1000, height: 1000)
                } else {
                    let dx = max(rect.size.width * 0.5, 200)
                    let dy = max(rect.size.height * 0.5, 200)
                    padded = rect.insetBy(dx: -dx, dy: -dy)
                }
                mapView.setVisibleMapRect(padded, animated: true)
                mapView.deselectAnnotation(cluster, animated: false)
                return
            }

            // Visual halo: amber glow ring around selected marker. Mirrors web's
            // 3px blue halo on selected markers, recolored to fit the iOS palette.
            UIView.animate(withDuration: 0.18) {
                view.transform = CGAffineTransform(scaleX: 1.18, y: 1.18)
            }
            view.layer.shadowColor = UIColor(Color.sunAccent).cgColor
            view.layer.shadowRadius = 8
            view.layer.shadowOpacity = 0.7
            view.layer.shadowOffset = .zero

            guard !isUpdating else { return }
            if let ta = view.annotation as? TripItemAnnotation {
                selectedID = ta.item.id
            }
        }

        func mapView(_ mapView: MKMapView, didDeselect view: MKAnnotationView) {
            UIView.animate(withDuration: 0.18) {
                view.transform = .identity
            }
            view.layer.shadowOpacity = 0

            guard !isUpdating else { return }
            selectedID = nil
        }
    }
}
