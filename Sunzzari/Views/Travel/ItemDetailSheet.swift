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
                            .font(.title3.weight(.bold))
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
                                    .font(.caption)
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
                                .font(.caption)
                                .foregroundStyle(type.color)
                        }

                        if !item.legCity.isEmpty {
                            Label(item.legCity, systemImage: "mappin")
                                .font(.caption)
                                .foregroundStyle(Color.sunSecondary)
                        }

                        if let dist = distanceToItem {
                            Label(dist, systemImage: "location")
                                .font(.caption)
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
                            badge("Reservation Required", color: Color(hex: "#F97316"))
                        }
                    }

                    // Date
                    if let date = item.displayDate {
                        Label(date, systemImage: "calendar")
                            .font(.subheadline)
                            .foregroundStyle(Color.sunSecondary)
                    }

                    // Notes
                    if !item.notes.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Notes")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.sunSecondary)
                            Text(item.notes)
                                .font(.subheadline)
                                .foregroundStyle(Color.sunText)
                        }
                    }

                    Divider().overlay(Color.white.opacity(0.1))

                    // Actions
                    HStack(spacing: 12) {
                        if item.hasCoordinates {
                            Button {
                                openInMaps()
                            } label: {
                                Label("Open in Maps", systemImage: "map.fill")
                                    .font(.subheadline.weight(.medium))
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
                                .font(.subheadline.weight(.medium))
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
            .font(.caption2.weight(.medium))
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
        guard let lat = item.latitude, let lon = item.longitude else { return }
        let coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        let placemark = MKPlacemark(coordinate: coord)
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = item.name
        mapItem.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
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
