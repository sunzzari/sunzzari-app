import SwiftUI

struct TripFilterBar: View {
    let items: [TripItem]
    @Binding var activeStatuses: Set<TripItem.ItemStatus>
    @Binding var activeTypes: Set<TripItem.ItemType>
    @Binding var activeLegs: Set<String>
    @Binding var searchQuery: String
    @Binding var nearMeActive: Bool

    private var uniqueLegs: [String] {
        Array(Set(items.map(\.legCity).filter { !$0.isEmpty })).sorted()
    }

    private var hasActiveFilters: Bool {
        !activeStatuses.isEmpty || !activeTypes.isEmpty || !activeLegs.isEmpty || nearMeActive
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Search
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .font(.caption)
                        .foregroundStyle(Color.sunSecondary)
                    TextField("Search", text: $searchQuery)
                        .font(.caption)
                        .foregroundStyle(Color.sunText)
                        .frame(width: searchQuery.isEmpty ? 60 : 120)
                    if !searchQuery.isEmpty {
                        Button { searchQuery = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption2)
                                .foregroundStyle(Color.sunSecondary)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.sunSurface)
                .clipShape(Capsule())

                // Near Me
                chipButton(
                    label: "Near Me",
                    icon: "location.fill",
                    isActive: nearMeActive
                ) {
                    nearMeActive.toggle()
                }

                // Status chips
                ForEach(TripItem.ItemStatus.allCases, id: \.self) { status in
                    chipButton(
                        label: status.rawValue,
                        isActive: activeStatuses.contains(status)
                    ) {
                        if activeStatuses.contains(status) {
                            activeStatuses.remove(status)
                        } else {
                            activeStatuses.insert(status)
                        }
                    }
                }

                // Leg/City chips
                ForEach(uniqueLegs, id: \.self) { leg in
                    chipButton(
                        label: leg,
                        icon: "mappin",
                        isActive: activeLegs.contains(leg)
                    ) {
                        if activeLegs.contains(leg) {
                            activeLegs.remove(leg)
                        } else {
                            activeLegs.insert(leg)
                        }
                    }
                }

                // Clear All
                if hasActiveFilters {
                    Button {
                        activeStatuses.removeAll()
                        activeTypes.removeAll()
                        activeLegs.removeAll()
                        nearMeActive = false
                    } label: {
                        Text("Clear")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(Color.sunAccent)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .background(Color.sunBackground.opacity(0.9))
    }

    private func chipButton(label: String, icon: String? = nil, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon {
                    Image(systemName: icon)
                        .font(.caption2)
                }
                Text(label)
                    .font(.caption2.weight(.medium))
            }
            .foregroundStyle(isActive ? Color.sunBackground : Color.sunText)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isActive ? Color.sunAccent : Color.sunSurface)
            .clipShape(Capsule())
        }
    }
}
