import SwiftUI
import MapKit

// MARK: - Bridge (SwiftUI -> UIKit imperative calls)

final class TripMapBridge {
    weak var mapView: MKMapView?

    func fitAll(animated: Bool = true) {
        guard let mv = mapView else { return }
        let anns = mv.annotations.filter { !($0 is MKUserLocation) }
        guard !anns.isEmpty else { return }
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
    let totalMappedCount: Int
    let filterKey: String
    @Binding var selectedID: String?
    let bridge: TripMapBridge

    func makeCoordinator() -> Coordinator { Coordinator(selectedID: $selectedID) }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsUserLocation = true
        map.mapType = .standard
        map.overrideUserInterfaceStyle = .dark
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

            let placed = map.annotations.filter { $0 is TripItemAnnotation }.count
            if !coordinator.didFitAll && totalMappedCount > 0 && placed >= totalMappedCount {
                coordinator.didFitAll = true
                coordinator.lastFilterKey = filterKey
                let anns = map.annotations.filter { !($0 is MKUserLocation) }
                DispatchQueue.main.async { map.showAnnotations(anns, animated: true) }
            }
        }

        // Re-fit when filter changes
        if coordinator.didFitAll && filterKey != coordinator.lastFilterKey {
            coordinator.lastFilterKey = filterKey
            DispatchQueue.main.async {
                let anns = map.annotations.filter { !($0 is MKUserLocation) }
                if !anns.isEmpty { map.showAnnotations(anns, animated: true) }
            }
        }

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
        var didFitAll = false
        var lastFilterKey: String = ""

        init(selectedID: Binding<String?>) {
            _selectedID = selectedID
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

            let type = ta.item.type ?? .other
            v.markerTintColor = UIColor(Color(hex: type.colorHex))
            v.glyphImage = UIImage(systemName: type.sfSymbol)

            // Selected state: larger display priority
            let isSelected = ta.item.id == selectedID
            v.displayPriority = isSelected ? .required : .defaultHigh

            return v
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            guard !isUpdating else { return }
            if let ta = view.annotation as? TripItemAnnotation {
                selectedID = ta.item.id
            }
        }

        func mapView(_ mapView: MKMapView, didDeselect view: MKAnnotationView) {
            guard !isUpdating else { return }
            selectedID = nil
        }
    }
}
