import SwiftUI
import MapKit
import UIKit

// MARK: - Annotation

final class StatusAnnotation: NSObject, MKAnnotation {
    let entry: StatusEntry
    @objc dynamic var coordinate: CLLocationCoordinate2D
    var title: String? { entry.name }

    init(entry: StatusEntry, coordinate: CLLocationCoordinate2D) {
        self.entry = entry
        self.coordinate = coordinate
    }
}

// MARK: - UIViewRepresentable

struct StatusMKMap: UIViewRepresentable {
    let annotations: [StatusAnnotation]

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsUserLocation = false
        map.mapType = .standard
        map.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: "status")
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        // Remove old status annotations
        let toRemove = map.annotations.filter { $0 is StatusAnnotation }
        map.removeAnnotations(toRemove)
        map.addAnnotations(annotations)

        // Fit both pins
        if !annotations.isEmpty {
            let anns = map.annotations.filter { !($0 is MKUserLocation) }
            DispatchQueue.main.async {
                map.showAnnotations(anns, animated: true)
                // Add some padding by zooming out slightly
                var region = map.region
                region.span.latitudeDelta  *= 1.5
                region.span.longitudeDelta *= 1.5
                map.setRegion(region, animated: false)
            }
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let sa = annotation as? StatusAnnotation else { return nil }
            let v = mapView.dequeueReusableAnnotationView(
                withIdentifier: "status",
                for: annotation
            ) as! MKMarkerAnnotationView
            v.canShowCallout = false
            v.titleVisibility = .hidden
            v.subtitleVisibility = .hidden

            if sa.entry.isHummingbird {
                v.glyphText = "🕊️"
                v.markerTintColor = UIColor(red: 0.22, green: 0.74, blue: 0.97, alpha: 1) // sky blue #38BDF8
            } else {
                v.glyphText = "🌿"
                v.markerTintColor = UIColor(red: 0.29, green: 0.87, blue: 0.50, alpha: 1) // green #4ADE80
            }
            return v
        }
    }
}

// MARK: - SwiftUI wrapper

struct StatusMapView: View {
    let entries: [StatusEntry]

    private var annotations: [StatusAnnotation] {
        entries.compactMap { entry in
            guard let coord = entry.coordinate else { return nil }
            return StatusAnnotation(entry: entry, coordinate: coord)
        }
    }

    var body: some View {
        if annotations.isEmpty {
            ZStack {
                Color.sunSurface
                VStack(spacing: 8) {
                    Image(systemName: "location.slash")
                        .font(.title2)
                        .foregroundStyle(Color.sunSecondary)
                    Text("No location data yet")
                        .font(.caption)
                        .foregroundStyle(Color.sunSecondary)
                }
            }
        } else {
            StatusMKMap(annotations: annotations)
        }
    }
}
