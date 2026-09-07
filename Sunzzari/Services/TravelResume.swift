import Foundation

/// Remembers the trip screen Elisa had open, so launching the app during a trip
/// puts her back on it instead of on Home.
///
/// Elisa, 2026-09-06: *"make sure to always allow me to open the app directly to
/// the travel page if thats what i had open before. before it was always taking
/// me to the home page. but when im traveling i want to go directly to the
/// travel page i was on."*
///
/// Deliberately narrow. It stores an id and a timestamp, not a navigation
/// graph, because a serialized nav path that no longer matches the app is a
/// launch crash and this is a screen she opens five times a day.
enum TravelResume {
    private static let tripKey = "sunzzari_resume_trip_id"
    private static let seenKey = "sunzzari_resume_seen_at"

    /// How long a trip screen stays resumable after she last looked at it.
    /// Covers "put the phone down at dinner, pick it up at breakfast" without
    /// resurrecting a trip she finished months ago.
    private static let window: TimeInterval = 36 * 60 * 60

    /// Called when the trip day screen appears.
    static func remember(tripID: String) {
        UserDefaults.standard.set(tripID, forKey: tripKey)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: seenKey)
    }

    /// Called when she deliberately leaves travel, so the app stops resuming it.
    static func forget() {
        UserDefaults.standard.removeObject(forKey: tripKey)
        UserDefaults.standard.removeObject(forKey: seenKey)
    }

    /// The trip to reopen on launch, or nil.
    ///
    /// Resumes when the trip is LIVE today regardless of age, because during a
    /// trip that is exactly what she asked for. Otherwise it needs to have been
    /// seen recently, so a finished trip does not keep hijacking the launch.
    static func tripToResume(from trips: [Trip]) -> Trip? {
        guard let id = UserDefaults.standard.string(forKey: tripKey),
              let trip = trips.first(where: {
                  $0.id.replacingOccurrences(of: "-", with: "") == id.replacingOccurrences(of: "-", with: "")
              })
        else { return nil }

        if trip.isLiveToday { return trip }

        let seen = UserDefaults.standard.double(forKey: seenKey)
        guard seen > 0, Date().timeIntervalSince1970 - seen < window else { return nil }
        // Never resume something already over.
        guard trip.status != .completed, trip.status != .cancelled else { return nil }
        return trip
    }

    /// Trips read from the on-disk cache, so a resume works with no signal.
    /// Returns an empty array rather than throwing: failing to resume must
    /// never stop the app from launching.
    static func cachedTrips() -> [Trip] {
        TravelService.shared.tripsDiskCache() ?? []
    }
}
