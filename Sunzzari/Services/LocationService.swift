import Foundation
import CoreLocation
import UIKit

final class LocationService: @unchecked Sendable {
    static let shared = LocationService()
    private init() {}

    private let manager: CLLocationManager = {
        let m = CLLocationManager()
        m.desiredAccuracy = kCLLocationAccuracyHundredMeters
        m.distanceFilter = kCLDistanceFilterNone
        return m
    }()

    private let delegate = LocationDelegate()

    // UserDefaults keys for last known own location
    static let latKey = "sunzzari_own_lat"
    static let lonKey = "sunzzari_own_lon"

    func requestAlwaysAuthorization() async {
        manager.delegate = delegate
        let status = manager.authorizationStatus
        if status == .notDetermined {
            manager.requestAlwaysAuthorization()
        } else if status == .authorizedWhenInUse {
            manager.requestAlwaysAuthorization()
        }
    }

    func startSignificantLocationChanges() {
        manager.delegate = delegate
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = false
        manager.startMonitoringSignificantLocationChanges()
    }

    /// Request a one-shot current location update (fires delegate once).
    func requestCurrentLocation() {
        manager.delegate = delegate
        manager.requestLocation()
    }

    /// Last known own location from UserDefaults (instant, no network)
    var lastKnownCoordinate: CLLocationCoordinate2D? {
        let lat = UserDefaults.standard.double(forKey: LocationService.latKey)
        let lon = UserDefaults.standard.double(forKey: LocationService.lonKey)
        guard lat != 0 || lon != 0 else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}

// MARK: - Delegate

private final class LocationDelegate: NSObject, CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        let coord = loc.coordinate
        // Persist last-known location
        UserDefaults.standard.set(coord.latitude,  forKey: LocationService.latKey)
        UserDefaults.standard.set(coord.longitude, forKey: LocationService.lonKey)
        // Push to Notion in background (fire-and-forget)
        let pageID = ownPageID()
        guard !pageID.isEmpty else { return }
        Task {
            try? await StatusService.shared.updateLocation(coord, for: pageID)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Silently ignore — location is best-effort
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedAlways {
            manager.allowsBackgroundLocationUpdates = true
            manager.pausesLocationUpdatesAutomatically = false
            manager.startMonitoringSignificantLocationChanges()
        }
    }

    private func ownPageID() -> String {
        AppIdentity.isBranch
            ? Constants.Status.branchPageID
            : Constants.Status.hummingbirdPageID
    }
}

