import SwiftUI
import MapKit
import CoreLocation

struct ReadDaySection: View {

    let day: DayBundle
    let selectedID: String?
    let onSelect: (TripItem) -> Void

    @State private var bridge = TripMapBridge()
    @State private var localSelectedID: String? = nil

    private static let displayHeader: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d"
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    private var allAnnotations: [TripItemAnnotation] {
        day.allItems.compactMap { item in
            guard let lat = item.latitude, let lon = item.longitude else { return nil }
            return TripItemAnnotation(item: item, coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon))
        }
    }

    private var routeAnnotations: [TripItemAnnotation] {
        day.confirmed.compactMap { item in
            guard let lat = item.latitude, let lon = item.longitude else { return nil }
            return TripItemAnnotation(item: item, coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(Self.displayHeader.string(from: day.date))
                .font(.system(.title3, design: .serif, weight: .semibold))
                .foregroundStyle(Color.sunText)

            Rectangle()
                .fill(Color.sunSecondary.opacity(0.3))
                .frame(height: 1)

            TripMKMap(
                annotations: allAnnotations,
                filterKey: "day-\(day.dateString)",
                selectedID: mapSelectionBinding,
                bridge: bridge,
                routeAnnotations: routeAnnotations,
                interactive: true,
                alwaysAutoFit: true
            )
            .frame(height: 240)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            if !day.confirmed.isEmpty {
                sectionHeader("Confirmed plan")
                ForEach(day.confirmed) { item in
                    proseRow(for: item, isPossibility: false)
                }
            }

            if !day.possibilities.isEmpty {
                sectionHeader("Could fit in")
                ForEach(day.possibilities) { item in
                    proseRow(for: item, isPossibility: true)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(Color.sunSurface.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // Forward map-driven selections to the parent so a marker tap behaves like a row tap.
    private var mapSelectionBinding: Binding<String?> {
        Binding(
            get: { selectedID ?? localSelectedID },
            set: { newID in
                localSelectedID = newID
                if let id = newID, let item = day.allItems.first(where: { $0.id == id }) {
                    onSelect(item)
                }
            }
        )
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(.caption, design: .serif, weight: .semibold))
            .foregroundStyle(Color.sunSecondary)
            .padding(.top, 4)
    }

    @ViewBuilder
    private func proseRow(for item: TripItem, isPossibility: Bool) -> some View {
        Button { onSelect(item) } label: {
            HStack(alignment: .top, spacing: 8) {
                Circle()
                    .fill(item.status?.color ?? Color.sunSecondary)
                    .frame(width: 6, height: 6)
                    .padding(.top, 7)

                VStack(alignment: .leading, spacing: 2) {
                    Text(proseTitle(for: item))
                        .font(.system(.body, design: .serif, weight: isPossibility ? .regular : .medium))
                        .foregroundStyle(Color.sunText)
                        .multilineTextAlignment(.leading)

                    if isPossibility, let proximity = ProximityHelper.proximityLine(for: item, in: day.confirmed) {
                        Text(proximity)
                            .font(.system(.caption2, design: .serif))
                            .foregroundStyle(Color.sunAccent)
                    }

                    if !item.notes.isEmpty {
                        Text(item.notes)
                            .font(.system(.caption, design: .serif))
                            .foregroundStyle(Color.sunSecondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
            .background(selectedID == item.id ? Color.sunAccent.opacity(0.12) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    private func proseTitle(for item: TripItem) -> String {
        let prefix: String? = {
            switch item.type {
            case .hotel:      return "Stay: "
            case .carRental:  return "Pickup: "
            default:          return nil
            }
        }()
        let venuePart = item.venue.isEmpty ? "" : " — \(item.venue)"
        return "\(prefix ?? "")\(item.name)\(venuePart)"
    }
}
