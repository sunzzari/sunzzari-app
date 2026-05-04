import Foundation
import CoreLocation

enum ProximityHelper {

    private static let detourMultiplier: Double = 1.3
    private static let walkingMetersPerMinute: Double = 80   // ~5 km/h
    private static let drivingMetersPerMinute: Double = 500  // ~30 km/h urban
    private static let walkDriveThresholdMeters: Double = 1500

    /// Returns the nearest confirmed item to `item` based on coordinates.
    /// Returns nil if `item` has no coordinates or `confirmed` has no items with coordinates.
    static func nearestConfirmed(to item: TripItem, in confirmed: [TripItem]) -> (item: TripItem, distanceMeters: Double)? {
        guard let lat = item.latitude, let lon = item.longitude else { return nil }
        let origin = CLLocation(latitude: lat, longitude: lon)

        var best: (TripItem, Double)?
        for c in confirmed where c.id != item.id {
            guard let cLat = c.latitude, let cLon = c.longitude else { continue }
            let d = origin.distance(from: CLLocation(latitude: cLat, longitude: cLon))
            if best == nil || d < best!.1 { best = (c, d) }
        }
        return best.map { (item: $0.0, distanceMeters: $0.1) }
    }

    /// Renders a short hint like "~5 min walk" or "~12 min drive".
    /// Distance is multiplied by `detourMultiplier` to roughly account for non-straight paths.
    static func walkingHint(distanceMeters: Double) -> String {
        let adjusted = distanceMeters * detourMultiplier
        if adjusted < walkDriveThresholdMeters {
            let mins = max(1, Int((adjusted / walkingMetersPerMinute).rounded()))
            return "~\(mins) min walk"
        } else {
            let mins = max(1, Int((adjusted / drivingMetersPerMinute).rounded()))
            return "~\(mins) min drive"
        }
    }

    /// Convenience: build "~5 min walk from Le Tout-Paris" or returns nil if no nearby confirmed.
    static func proximityLine(for item: TripItem, in confirmed: [TripItem]) -> String? {
        guard let nearest = nearestConfirmed(to: item, in: confirmed) else { return nil }
        let hint = walkingHint(distanceMeters: nearest.distanceMeters)
        return "\(hint) from \(nearest.item.name)"
    }
}
