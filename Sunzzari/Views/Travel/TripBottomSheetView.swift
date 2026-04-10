import SwiftUI
import CoreLocation

struct TripBottomSheetView: View {
    let items: [TripItem]
    @Binding var selectedID: String?
    let userLocation: CLLocation?
    let onSelect: (TripItem) -> Void

    @State private var sheetOffset: CGFloat = 0
    @State private var isExpanded = false

    private let collapsedHeight: CGFloat = 56
    private let expandedFraction: CGFloat = 0.55

    private var mappedCount: Int { items.filter(\.hasCoordinates).count }

    private var selectedItem: TripItem? {
        guard let id = selectedID else { return nil }
        return items.first { $0.id == id }
    }

    var body: some View {
        GeometryReader { geo in
            let maxHeight = geo.size.height * expandedFraction

            VStack(spacing: 0) {
                // Handle + header
                headerView
                    .onTapGesture {
                        withAnimation(.spring(response: 0.35)) {
                            isExpanded.toggle()
                            if !isExpanded { selectedID = nil }
                        }
                    }

                if isExpanded {
                    // Item list
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(items) { item in
                                compactItemRow(item)
                            }
                        }
                    }
                    .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: isExpanded ? maxHeight : collapsedHeight, alignment: .top)
            .background(Color.sunSurface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.3), radius: 8, y: -2)
            .offset(y: sheetOffset)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        let delta = value.translation.height
                        if isExpanded {
                            sheetOffset = max(0, delta)
                        } else {
                            sheetOffset = min(0, delta)
                        }
                    }
                    .onEnded { value in
                        let velocity = value.predictedEndTranslation.height
                        withAnimation(.spring(response: 0.35)) {
                            if isExpanded && (value.translation.height > 60 || velocity > 300) {
                                isExpanded = false
                            } else if !isExpanded && (value.translation.height < -60 || velocity < -300) {
                                isExpanded = true
                            }
                            sheetOffset = 0
                        }
                    }
            )
            .frame(maxHeight: .infinity, alignment: .bottom)
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
    }

    private var headerView: some View {
        VStack(spacing: 6) {
            // Drag handle
            Capsule()
                .fill(Color.white.opacity(0.3))
                .frame(width: 36, height: 4)
                .padding(.top, 8)

            HStack {
                if let item = selectedItem {
                    if let type = item.type {
                        Image(systemName: type.sfSymbol)
                            .foregroundStyle(type.color)
                            .font(.caption)
                    }
                    Text(item.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.sunText)
                        .lineLimit(1)
                } else {
                    Text("\(items.count) items")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.sunText)
                    Text("\(mappedCount) mapped")
                        .font(.caption)
                        .foregroundStyle(Color.sunSecondary)
                }

                Spacer()

                Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                    .font(.caption)
                    .foregroundStyle(Color.sunSecondary)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }

    private func compactItemRow(_ item: TripItem) -> some View {
        Button {
            onSelect(item)
            withAnimation(.spring(response: 0.35)) { isExpanded = false }
        } label: {
            HStack(spacing: 8) {
                if let type = item.type {
                    Image(systemName: type.sfSymbol)
                        .foregroundStyle(type.color)
                        .font(.caption)
                        .frame(width: 20)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(item.name)
                        .font(.subheadline)
                        .foregroundStyle(Color.sunText)
                        .lineLimit(1)

                    if !item.legCity.isEmpty {
                        Text(item.legCity)
                            .font(.caption)
                            .foregroundStyle(Color.sunSecondary)
                    }
                }

                Spacer()

                if let loc = userLocation, let lat = item.latitude, let lon = item.longitude {
                    let dist = loc.distance(from: CLLocation(latitude: lat, longitude: lon))
                    Text(formatDistance(dist))
                        .font(.caption2)
                        .foregroundStyle(Color.sunSecondary)
                }

                if let status = item.status {
                    Circle()
                        .fill(status.color)
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 16)
            .background(item.id == selectedID ? Color.sunAccent.opacity(0.15) : Color.clear)
        }
        .buttonStyle(.plain)
    }

    private func formatDistance(_ meters: Double) -> String {
        if meters < 1000 { return "\(Int(meters))m" }
        return String(format: "%.1fkm", meters / 1000)
    }
}
