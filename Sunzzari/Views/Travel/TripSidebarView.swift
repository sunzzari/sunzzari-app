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
            HStack(spacing: 6) {
                Text("\(items.count) items")
                    .font(.system(.caption, design: .serif, weight: .medium))
                    .foregroundStyle(Color.sunText)
                Text("· \(mappedCount) mapped")
                    .font(.system(.caption, design: .serif))
                    .foregroundStyle(Color.sunSecondary)
                if userLocation != nil {
                    Text("· sorted by distance")
                        .font(.system(.caption, design: .serif))
                        .foregroundStyle(Color(hex: "#3B82F6"))
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.sunSurface)

            // Item list
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                        ForEach(groupedByType, id: \.0) { type, group in
                            Section {
                                ForEach(group) { item in
                                    itemRow(item)
                                        .id(item.id)
                                }
                            } header: {
                                sectionHeader(type: type, count: group.count)
                            }
                        }

                        if !untypedItems.isEmpty {
                            Section {
                                ForEach(untypedItems) { item in
                                    itemRow(item)
                                        .id(item.id)
                                }
                            } header: {
                                untypedHeader
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

    private var untypedHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "questionmark.circle")
            Text("Other (\(untypedItems.count))")
        }
        .font(.system(.caption, design: .serif, weight: .semibold))
        .foregroundStyle(Color.sunSecondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.sunBackground)
    }

    private func sectionHeader(type: TripItem.ItemType, count: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: type.sfSymbol)
                .foregroundStyle(type.color)
            Text("\(type.rawValue) (\(count))")
        }
        .font(.system(.caption, design: .serif, weight: .semibold))
        .foregroundStyle(Color.sunSecondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.sunBackground.opacity(0.95))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(type.color)
                .frame(width: 3)
        }
    }

    private func itemRow(_ item: TripItem) -> some View {
        let isSelected = item.id == selectedID
        let statusColor = item.status?.color ?? Color.sunSecondary
        return Button {
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
                        .font(.system(.subheadline, design: .serif, weight: .medium))
                        .foregroundStyle(Color.sunText)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        if !item.legCity.isEmpty {
                            Text(item.legCity)
                                .font(.system(.caption, design: .serif))
                                .foregroundStyle(Color.sunSecondary)
                        }
                        if let date = item.displayDate {
                            Text(date)
                                .font(.system(.caption, design: .serif))
                                .foregroundStyle(Color.sunSecondary)
                        }
                    }

                    if !item.hasCoordinates {
                        HStack(spacing: 3) {
                            Image(systemName: "location.slash")
                            Text("Not geocoded")
                        }
                        .font(.system(.caption2, design: .serif))
                        .foregroundStyle(Color.sunAccent.opacity(0.7))
                    }
                }

                Spacer()

                // Distance
                if let loc = userLocation, let lat = item.latitude, let lon = item.longitude {
                    let dist = loc.distance(from: CLLocation(latitude: lat, longitude: lon))
                    Text(formatDistance(dist))
                        .font(.system(.caption2, design: .serif, weight: .medium))
                        .foregroundStyle(Color(hex: "#3B82F6"))
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(isSelected ? Color.sunAccent.opacity(0.12) : Color.clear)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(isSelected ? Color.sunAccent : statusColor)
                    .frame(width: isSelected ? 3 : 2)
            }
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
