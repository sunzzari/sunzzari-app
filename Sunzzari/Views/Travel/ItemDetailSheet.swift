import SwiftUI
import MapKit
import CoreLocation

struct ItemDetailSheet: View {
    let item: TripItem
    let userLocation: CLLocation?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Priority color bar
                    if let priority = item.priority {
                        Rectangle()
                            .fill(priority.color)
                            .frame(height: 4)
                            .clipShape(Capsule())
                    }

                    // Name + copy
                    HStack {
                        Text(item.name)
                            .font(.system(.title3, design: .serif, weight: .bold))
                            .fontDesign(.serif)
                            .foregroundStyle(Color.sunText)

                        Spacer()

                        if !item.venue.isEmpty || !item.legCity.isEmpty {
                            Button {
                                let text = [item.venue, item.legCity]
                                    .filter { !$0.isEmpty }
                                    .joined(separator: ", ")
                                UIPasteboard.general.string = text
                            } label: {
                                Image(systemName: "doc.on.doc")
                                    .font(.system(.caption, design: .serif))
                                    .foregroundStyle(Color.sunSecondary)
                                    .padding(8)
                                    .background(Color.sunSurface)
                                    .clipShape(Circle())
                            }
                        }
                    }

                    // Type + city + distance
                    HStack(spacing: 12) {
                        if let type = item.type {
                            Label(type.rawValue, systemImage: type.sfSymbol)
                                .font(.system(.caption, design: .serif))
                                .foregroundStyle(type.color)
                        }

                        if !item.legCity.isEmpty {
                            Label(item.legCity, systemImage: "mappin")
                                .font(.system(.caption, design: .serif))
                                .foregroundStyle(Color.sunSecondary)
                        }

                        if let dist = distanceToItem {
                            Label(dist, systemImage: "location")
                                .font(.system(.caption, design: .serif))
                                .foregroundStyle(Color.sunSecondary)
                        }
                    }

                    // Badges
                    HStack(spacing: 8) {
                        if let status = item.status {
                            badge(status.rawValue, color: status.color)
                        }
                        if let priority = item.priority {
                            badge(priority.rawValue, color: priority.color)
                        }
                        if item.reservationRequired {
                            badge(
                                item.reservationMade ? "Reservation Made" : "Reservation Required",
                                color: Color(hex: item.reservationMade ? "#22C55E" : "#F97316")
                            )
                        }
                    }

                    // Date
                    if let date = item.displayDate {
                        Label(date, systemImage: "calendar")
                            .font(.system(.subheadline, design: .serif))
                            .foregroundStyle(Color.sunSecondary)
                    }

                    // Address
                    if !item.address.isEmpty {
                        Label(item.address, systemImage: "mappin.and.ellipse")
                            .font(.system(.subheadline, design: .serif))
                            .foregroundStyle(Color.sunText)
                    }

                    // Confirmation number + who it was booked through. These
                    // live in Notion and were shown nowhere until 2026-09-06.
                    if let line = item.confirmationLine {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Confirmation")
                                .font(.system(.caption, design: .serif, weight: .semibold))
                                .foregroundStyle(Color.sunSecondary)
                            HStack {
                                Text(line)
                                    .font(.system(.subheadline, design: .serif, weight: .semibold))
                                    .foregroundStyle(Color(hex: "#22C55E"))
                                    .monospacedDigit()
                                    .textSelection(.enabled)
                                if !item.confirmationNumber.isEmpty {
                                    Button {
                                        UIPasteboard.general.string = item.confirmationNumber
                                    } label: {
                                        Image(systemName: "doc.on.doc")
                                            .font(.system(.caption, design: .serif))
                                            .foregroundStyle(Color.sunSecondary)
                                    }
                                }
                            }
                        }
                    }

                    // Notes
                    if !item.notes.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Notes")
                                .font(.system(.caption, design: .serif, weight: .semibold))
                                .foregroundStyle(Color.sunSecondary)
                            Text(item.notes)
                                .font(.system(.subheadline, design: .serif))
                                .foregroundStyle(Color.sunText)
                        }
                    }

                    Divider().overlay(Color.white.opacity(0.1))

                    // Actions
                    HStack(spacing: 12) {
                        if item.hasCoordinates || !item.address.isEmpty || !item.venue.isEmpty {
                            Button {
                                openInMaps()
                            } label: {
                                Label("Open in Maps", systemImage: "map.fill")
                                    .font(.system(.subheadline, design: .serif, weight: .medium))
                                    .foregroundStyle(Color.sunBackground)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(Color.sunAccent)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                        }

                        Button {
                            openInNotion()
                        } label: {
                            Label("Notion", systemImage: "link")
                                .font(.system(.subheadline, design: .serif, weight: .medium))
                                .foregroundStyle(Color.sunText)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color.sunSurface)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
                .padding()
            }
            .background(Color.sunBackground)
            .navigationTitle(item.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(Color.sunSurface, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.sunAccent)
                }
            }
        }
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(.caption2, design: .serif, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.15))
            .clipShape(Capsule())
    }

    private var distanceToItem: String? {
        guard let loc = userLocation, let lat = item.latitude, let lon = item.longitude else { return nil }
        let dist = loc.distance(from: CLLocation(latitude: lat, longitude: lon))
        if dist < 1000 { return "\(Int(dist))m" }
        return String(format: "%.1fkm", dist / 1000)
    }

    private func openInMaps() {
        if let lat = item.latitude, let lon = item.longitude {
            let coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            let mapItem = MKMapItem(placemark: MKPlacemark(coordinate: coord))
            mapItem.name = item.name
            mapItem.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
            return
        }
        // No geocode yet. An address or the venue name still gets her there,
        // which beats a button that does nothing.
        let target = !item.address.isEmpty ? item.address : (item.venue.isEmpty ? item.name : item.venue)
        let query = [target, item.legCity].filter { !$0.isEmpty }.joined(separator: ", ")
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "http://maps.apple.com/?q=\(encoded)") else { return }
        UIApplication.shared.open(url)
    }

    private func openInNotion() {
        let cleanID = item.id.replacingOccurrences(of: "-", with: "")
        if let appURL = URL(string: "notion://www.notion.so/\(cleanID)") {
            UIApplication.shared.open(appURL, options: [:]) { success in
                if !success, let webURL = URL(string: "https://www.notion.so/\(cleanID)") {
                    UIApplication.shared.open(webURL)
                }
            }
        }
    }
}
