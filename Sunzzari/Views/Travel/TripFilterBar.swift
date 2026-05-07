import SwiftUI

struct TripFilterBar: View {
    let items: [TripItem]
    let displayCount: Int
    @Binding var activeStatuses: Set<TripItem.ItemStatus>
    @Binding var activeTypes: Set<TripItem.ItemType>
    @Binding var activeLegs: Set<String>
    @Binding var searchQuery: String
    @Binding var nearMeActive: Bool

    private var uniqueLegs: [String] {
        Array(Set(items.map(\.legCity).filter { !$0.isEmpty })).sorted()
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                searchField

                nearMeChip

                groupLabel("Status:")
                ForEach(TripItem.ItemStatus.allCases, id: \.self) { status in
                    statusChip(status)
                }
                if !activeStatuses.isEmpty {
                    inlineClear { activeStatuses.removeAll() }
                }

                if uniqueLegs.count > 1 {
                    separator
                    groupLabel("Leg:")
                    ForEach(uniqueLegs, id: \.self) { leg in
                        legChip(leg)
                    }
                    if !activeLegs.isEmpty {
                        inlineClear { activeLegs.removeAll() }
                    }
                }

                Text("\(displayCount) items")
                    .font(.system(.caption2, design: .serif))
                    .foregroundStyle(Color.sunSecondary)
                    .padding(.leading, 8)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(Color.sunSurface)
    }

    // MARK: - Sub-views

    private var searchField: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .font(.system(.caption, design: .serif))
                .foregroundStyle(Color.sunSecondary)
            TextField("Search", text: $searchQuery)
                .font(.system(.caption, design: .serif))
                .foregroundStyle(Color.sunText)
                .frame(width: searchQuery.isEmpty ? 60 : 120)
            if !searchQuery.isEmpty {
                Button { searchQuery = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(.caption2, design: .serif))
                        .foregroundStyle(Color.sunSecondary)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.08))
        .clipShape(Capsule())
    }

    private var nearMeChip: some View {
        Button {
            nearMeActive.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "location.fill")
                    .font(.system(.caption2, design: .serif))
                Text("Near Me")
                    .font(.system(.caption2, design: .serif, weight: .medium))
            }
            .foregroundStyle(nearMeActive ? Color.sunBackground : Color.sunText)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(nearMeActive ? Color.sunAccent : Color.white.opacity(0.08))
            .clipShape(Capsule())
            .shadow(
                color: nearMeActive ? Color.sunAccent.opacity(0.4) : .clear,
                radius: nearMeActive ? 6 : 0
            )
        }
    }

    private func statusChip(_ status: TripItem.ItemStatus) -> some View {
        let isActive = activeStatuses.contains(status)
        let statusColor = Color(hex: status.colorHex)
        return Button {
            if isActive { activeStatuses.remove(status) }
            else { activeStatuses.insert(status) }
        } label: {
            Text(displayLabel(for: status))
                .font(.system(.caption2, design: .serif, weight: .medium))
                .foregroundStyle(isActive ? Color.white : statusColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(isActive ? statusColor : Color.clear)
                )
                .overlay(
                    Capsule().stroke(statusColor.opacity(isActive ? 1.0 : 0.3), lineWidth: 1)
                )
                .shadow(
                    color: isActive ? statusColor.opacity(0.4) : .clear,
                    radius: isActive ? 6 : 0
                )
        }
    }

    private func legChip(_ leg: String) -> some View {
        let isActive = activeLegs.contains(leg)
        let indigo = Color(hex: "#6366F1")
        return Button {
            if isActive { activeLegs.remove(leg) }
            else { activeLegs.insert(leg) }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "mappin")
                    .font(.system(.caption2, design: .serif))
                Text(leg)
                    .font(.system(.caption2, design: .serif, weight: .medium))
            }
            .foregroundStyle(isActive ? Color.white : indigo)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(isActive ? indigo : Color.clear)
            )
            .overlay(
                Capsule().stroke(indigo.opacity(isActive ? 1.0 : 0.3), lineWidth: 1)
            )
            .shadow(
                color: isActive ? indigo.opacity(0.4) : .clear,
                radius: isActive ? 6 : 0
            )
        }
    }

    private func groupLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(.caption2, design: .serif, weight: .semibold))
            .foregroundStyle(Color.sunSecondary)
    }

    private var separator: some View {
        Text("|")
            .font(.system(.caption2, design: .serif))
            .foregroundStyle(Color.white.opacity(0.15))
            .padding(.horizontal, 2)
    }

    private func inlineClear(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text("Clear")
                .font(.system(.caption2, design: .serif))
                .underline()
                .foregroundStyle(Color.sunSecondary)
        }
    }

    private func displayLabel(for status: TripItem.ItemStatus) -> String {
        status == .reservationPending ? "Res. Pending" : status.rawValue
    }
}
