import SwiftUI

// Reached as a nested destination from HubView (which owns the NavigationStack).
// Do NOT wrap in another NavigationStack — nested stacks cause double nav bars.
struct TravelView: View {
    var body: some View {
        TripListView()
    }
}
