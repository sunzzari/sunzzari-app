import Foundation
import MapKit

final class TripItemAnnotation: NSObject, MKAnnotation {
    let item: TripItem
    @objc dynamic var coordinate: CLLocationCoordinate2D

    /// Callout second line, when the caller has a better one than a trip item's.
    /// Around Town rides on this map and wants "Great · Sawtelle · Date night"
    /// rather than the raw comments field.
    let subtitleOverride: String?

    var title: String? { item.name }
    var subtitle: String? {
        if let subtitleOverride { return subtitleOverride.isEmpty ? nil : subtitleOverride }
        if !item.notes.isEmpty { return item.notes }
        var parts: [String] = []
        if let type = item.type { parts.append(type.rawValue) }
        if !item.legCity.isEmpty { parts.append(item.legCity) }
        if let status = item.status { parts.append(status.rawValue) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    init(item: TripItem, coordinate: CLLocationCoordinate2D, subtitleOverride: String? = nil) {
        self.item = item
        self.coordinate = coordinate
        self.subtitleOverride = subtitleOverride
    }
}
