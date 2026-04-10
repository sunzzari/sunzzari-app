import SwiftUI
import CoreLocation

struct TripSidebarView: View {
    let items: [TripItem]
    let selectedID: String?
    let userLocation: CLLocation?
    let onSelect: (TripItem) -> Void

    private var mappedCount: Int { items.filter(\.hasCoordinates).count }

    private var groupedByType: [(TripItem.ItemType, [TripItem])] {
        let typed = items.filter { $0.type != nil }
        let grouped = Dictionary(grouping: typed, by: { $0.type! })
        return TripItem.ItemType.allCases.compactMap { type in
            guard let group = grouped[type], !group.isEmpty else { return nil }
            return (type, group)
        }
    }

    private var untypedItems: [TripItem] {
        items.filter { $0.type == nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("\(items.count) items")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.sunText)
                Text("\(mappedCount) mapped")
                    .font(.caption)
                    .foregroundStyle(Color.sunSecondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.sunSurface)

            // Item list
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(groupedByType, id: \.0) { type, group in
                            sectionHeader(type: type, count: group.count)
                            ForEach(group) { item in
                                itemRow(item)
                                    .id(item.id)
                            }
                        }

                        if !untypedItems.isEmpty {
                            HStack(spacing: 6) {
                                Image(systemName: "questionmark.circle")
                                Text("Other (\(untypedItems.count))")
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.sunSecondary)
                            .padding(.horizontal, 12)
                            .padding(.top, 16)
                            .padding(.bottom, 4)

                            ForEach(untypedItems) { item in
                                itemRow(item)
                                    .id(item.id)
                            }
                        }
                    }
                    .padding(.bottom, 16)
                }
                .onChange(of: selectedID) { _, newID in
                    if let id = newID {
                        withAnimation { proxy.scrollTo(id, anchor: .center) }
                    }
                }
            }
        }
        .background(Color.sunBackground)
    }

    private func sectionHeader(type: TripItem.ItemType, count: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: type.sfSymbol)
                .foregroundStyle(type.color)
            Text("\(type.rawValue) (\(count))")
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(Color.sunSecondary)
        .padding(.horizontal, 12)
        .padding(.top, 16)
        .padding(.bottom, 4)
    }

    private func itemRow(_ item: TripItem) -> some View {
        Button {
            onSelect(item)
        } label: {
            HStack(spacing: 10) {
                // Priority dot
                if let priority = item.priority {
                    Circle()
                        .fill(priority.color)
                        .frame(width: 8, height: 8)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.sunText)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        if !item.legCity.isEmpty {
                            Text(item.legCity)
                                .font(.caption)
                                .foregroundStyle(Color.sunSecondary)
                        }
                        if let date = item.displayDate {
                            Text(date)
                                .font(.caption)
                                .foregroundStyle(Color.sunSecondary)
                        }
                    }
                }

                Spacer()

                // Distance
                if let loc = userLocation, let lat = item.latitude, let lon = item.longitude {
                    let dist = loc.distance(from: CLLocation(latitude: lat, longitude: lon))
                    Text(formatDistance(dist))
                        .font(.caption2)
                        .foregroundStyle(Color.sunSecondary)
                }

                // Status badge
                if let status = item.status {
                    Text(status.rawValue)
                        .font(.caption2)
                        .foregroundStyle(status.color)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(status.color.opacity(0.15))
                        .clipShape(Capsule())
                }

                // Unmapped
                if !item.hasCoordinates {
                    Image(systemName: "location.slash")
                        .font(.caption2)
                        .foregroundStyle(Color.sunSecondary)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(item.id == selectedID ? Color.sunAccent.opacity(0.15) : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(item.id == selectedID ? Color.sunAccent : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func formatDistance(_ meters: Double) -> String {
        if meters < 1000 {
            return "\(Int(meters))m"
        } else {
            return String(format: "%.1fkm", meters / 1000)
        }
    }
}
