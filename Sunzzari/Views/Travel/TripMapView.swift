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
}

// MARK: - UIViewRepresentable

struct TripMKMap: UIViewRepresentable {
    let annotations: [TripItemAnnotation]
    let filterKey: String
    @Binding var selectedID: String?
    let bridge: TripMapBridge

    /// When non-empty, renders a dashed polyline through these annotations in array order.
    /// Used to show the day's confirmed-stop route in Today/Read modes.
    var routeAnnotations: [TripItemAnnotation] = []

    var interactive: Bool = true

    // Per-day Read view sets this true so the map keeps framing "this day's" pins
    // as background geocoding fills them in (mirrors elisa-travel-map's fitKey).
    // The main trip map leaves it false so a manual zoom isn't yanked away.
    var alwaysAutoFit: Bool = false

    // When true, auto-fits include the user-location annotation so the user
    // dot stays in frame. Used when Near Me is active on the parent view.
    var fitIncludesUser: Bool = false

    func makeCoordinator() -> Coordinator { Coordinator(selectedID: $selectedID) }

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
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.isUpdating = true
        defer { coordinator.isUpdating = false }

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

        // Sync polyline overlay only when the route actually changes. Without
        // this gate, every selection-change-driven updateUIView would tear down
        // and recreate the polyline, flickering the dashed route on every tap.
        let routeKey = routeAnnotations.map(\.item.id).joined(separator: ",")
        if routeKey != coordinator.lastRouteKey {
            coordinator.lastRouteKey = routeKey
            let routeCoords = routeAnnotations.compactMap { $0.coordinate }
                .filter { CLLocationCoordinate2DIsValid($0) }
            let existingPolylines = map.overlays.compactMap { $0 as? MKPolyline }
            map.removeOverlays(existingPolylines)
            if routeCoords.count >= 2 {
                let line = MKPolyline(coordinates: routeCoords, count: routeCoords.count)
                map.addOverlay(line)
            }
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
        let annotationsChanged = annotations.count != coordinator.lastAnnotationCount
        let allowAutoRefit = alwaysAutoFit || !coordinator.userHasInteracted
        let countTrigger = alwaysAutoFit ? annotationsChanged : annotationsGrew
        if firstLoad || filterChanged || (countTrigger && allowAutoRefit) {
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

        // Sync selection
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

    final class Coordinator: NSObject, MKMapViewDelegate {
        @Binding var selectedID: String?
        var isUpdating = false
        var hasFittedInitially = false
        var lastFilterKey: String = ""
        var lastAnnotationCount = 0
        var lastRouteKey: String = ""
        var userHasInteracted = false

        init(selectedID: Binding<String?>) {
            _selectedID = selectedID
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

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation { return nil }

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
            v.canShowCallout = false
            v.titleVisibility = .hidden
            v.subtitleVisibility = .hidden

            // Color = STATUS (so confirmed/assigned/researching/shortlisted are visually distinct).
            // Glyph = TYPE (so the icon still tells you flight vs. hotel vs. restaurant).
            let status = ta.item.status ?? .researching
            v.markerTintColor = UIColor(Color(hex: status.colorHex))

            let type = ta.item.type ?? .other
            v.glyphImage = UIImage(systemName: type.sfSymbol)

            // Selected state: larger display priority
            let isSelected = ta.item.id == selectedID
            v.displayPriority = isSelected ? .required : .defaultHigh

            return v
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let line = overlay as? MKPolyline else { return MKOverlayRenderer(overlay: overlay) }
            let r = MKPolylineRenderer(polyline: line)
            r.strokeColor = UIColor(Color.sunAccent).withAlphaComponent(0.7)
            r.lineWidth = 2
            r.lineDashPattern = [4, 4]
            return r
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
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
