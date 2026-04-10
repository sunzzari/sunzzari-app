import Foundation
import MapKit

final class TripItemAnnotation: NSObject, MKAnnotation {
    let item: TripItem
    @objc dynamic var coordinate: CLLocationCoordinate2D
    var title: String? { item.name }

    init(item: TripItem, coordinate: CLLocationCoordinate2D) {
        self.item = item
        self.coordinate = coordinate
    }
}
