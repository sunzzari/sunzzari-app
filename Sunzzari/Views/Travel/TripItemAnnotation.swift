import Foundation
import MapKit

final class TripItemAnnotation: NSObject, MKAnnotation {
    let item: TripItem
    @objc dynamic var coordinate: CLLocationCoordinate2D
    var title: String? { item.name }
    var subtitle: String? {
        if !item.notes.isEmpty { return item.notes }
        var parts: [String] = []
        if let type = item.type { parts.append(type.rawValue) }
        if !item.legCity.isEmpty { parts.append(item.legCity) }
        if let status = item.status { parts.append(status.rawValue) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    init(item: TripItem, coordinate: CLLocationCoordinate2D) {
        self.item = item
        self.coordinate = coordinate
    }
}
