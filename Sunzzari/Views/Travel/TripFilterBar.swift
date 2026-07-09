import SwiftUI

// MARK: - Compact filter bar (one row: search + near me + filter button + count)

struct TripFilterBar: View {
    let items: [TripItem]
    let displayCount: Int
    @Binding var activeStatuses: Set<TripItem.ItemStatus>
    @Binding var activeTypes: Set<TripItem.ItemType>
    @Binding var activeLegs: Set<String>
    @Binding var filterReservationOnly: Bool
    @Binding var searchQuery: String
    @Binding var nearMeActive: Bool

    @State private var showFilters = false
    @FocusState private var searchFocused: Bool

    private var activeFilterCount: Int {
        activeStatuses.count + activeTypes.count + activeLegs.count + (filterReservationOnly ? 1 : 0)
    }

    var body: some View {
        HStack(spacing: 8) {
            searchField
            nearMeChip
            filterButton
            if activeFilterCount > 0 {
                clearFiltersButton
            }
            Spacer()
            Text("\(displayCount)")
                .font(.system(.caption2, design: .serif))
                .foregroundStyle(Color.sunSecondary)
                .padding(.trailing, 4)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.sunSurface)
        .sheet(isPresented: $showFilters) {
            TripFilterSheet(
                items: items,
                activeStatuses: $activeStatuses,
                activeTypes: $activeTypes,
                activeLegs: $activeLegs,
                filterReservationOnly: $filterReservationOnly
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private var searchField: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .font(.system(.caption, design: .serif))
                .foregroundStyle(Color.sunSecondary)
            TextField("Search", text: $searchQuery)
                .font(.system(.caption, design: .serif))
                .foregroundStyle(Color.sunText)
                .frame(width: searchQuery.isEmpty ? 60 : 110)
                .focused($searchFocused)
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done") { searchFocused = false }
                            .font(.system(.body, design: .serif))
                    }
                }
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
        Button { nearMeActive.toggle() } label: {
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
            .shadow(color: nearMeActive ? Color.sunAccent.opacity(0.4) : .clear, radius: nearMeActive ? 6 : 0)
        }
    }

    // One-tap clear for everything the filter sheet controls, so clearing
    // doesn't require opening the sheet. Search and Near Me keep their own
    // affordances (x in the field, chip toggle).
    private var clearFiltersButton: some View {
        Button {
            activeStatuses.removeAll()
            activeTypes.removeAll()
            activeLegs.removeAll()
            filterReservationOnly = false
        } label: {
            Image(systemName: "xmark")
                .font(.system(.caption2, design: .serif, weight: .semibold))
                .foregroundStyle(Color.sunText)
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.08))
                .clipShape(Capsule())
        }
    }

    private var filterButton: some View {
        Button { showFilters = true } label: {
            HStack(spacing: 4) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(.caption, design: .serif))
                if activeFilterCount > 0 {
                    Text("\(activeFilterCount)")
                        .font(.system(.caption2, design: .serif, weight: .bold))
                }
            }
            .foregroundStyle(activeFilterCount > 0 ? Color.sunBackground : Color.sunText)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(activeFilterCount > 0 ? Color.sunAccent : Color.white.opacity(0.08))
            .clipShape(Capsule())
            .shadow(color: activeFilterCount > 0 ? Color.sunAccent.opacity(0.4) : .clear, radius: activeFilterCount > 0 ? 6 : 0)
        }
    }
}

// MARK: - Filter sheet

struct TripFilterSheet: View {
    let items: [TripItem]
    @Binding var activeStatuses: Set<TripItem.ItemStatus>
    @Binding var activeTypes: Set<TripItem.ItemType>
    @Binding var activeLegs: Set<String>
    @Binding var filterReservationOnly: Bool

    @Environment(\.dismiss) private var dismiss

    private var uniqueLegs: [String] {
        Array(Set(items.map(\.legCity).filter { !$0.isEmpty })).sorted()
    }

    private var hasAnyFilter: Bool {
        !activeStatuses.isEmpty || !activeTypes.isEmpty || !activeLegs.isEmpty || filterReservationOnly
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    filterSection(title: "Status") {
                        ForEach(TripItem.ItemStatus.allCases, id: \.self) { status in
                            filterRow(
                                label: status.rawValue,
                                color: Color(hex: status.colorHex),
                                isOn: activeStatuses.contains(status)
                            ) {
                                if activeStatuses.contains(status) { activeStatuses.remove(status) }
                                else { activeStatuses.insert(status) }
                            }
                        }
                    }

                    filterSection(title: "Type") {
                        ForEach(TripItem.ItemType.allCases, id: \.self) { type in
                            filterRow(
                                label: type.rawValue,
                                icon: type.sfSymbol,
                                color: Color(hex: type.colorHex),
                                isOn: activeTypes.contains(type)
                            ) {
                                if activeTypes.contains(type) { activeTypes.remove(type) }
                                else { activeTypes.insert(type) }
                            }
                        }
                    }

                    if !uniqueLegs.isEmpty {
                        filterSection(title: "Destination") {
                            ForEach(uniqueLegs, id: \.self) { leg in
                                filterRow(
                                    label: leg,
                                    icon: "mappin",
                                    color: Color(hex: "#6366F1"),
                                    isOn: activeLegs.contains(leg)
                                ) {
                                    if activeLegs.contains(leg) { activeLegs.remove(leg) }
                                    else { activeLegs.insert(leg) }
                                }
                            }
                        }
                    }

                    filterSection(title: "Reservation") {
                        filterRow(
                            label: "Reservation Required",
                            icon: "calendar.badge.exclamationmark",
                            color: Color(hex: "#F97316"),
                            isOn: filterReservationOnly
                        ) {
                            filterReservationOnly.toggle()
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .background(Color.sunBackground)
            .navigationTitle("Filter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(Color.sunSurface, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.sunAccent)
                        .font(.system(.body, design: .serif))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if hasAnyFilter {
                        Button("Clear All") {
                            activeStatuses.removeAll()
                            activeTypes.removeAll()
                            activeLegs.removeAll()
                            filterReservationOnly = false
                        }
                        .foregroundStyle(Color.sunSecondary)
                        .font(.system(.subheadline, design: .serif))
                    }
                }
            }
        }
    }

    private func filterSection(title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.system(.caption2, design: .serif, weight: .semibold))
                .foregroundStyle(Color.sunSecondary)
                .tracking(0.8)
                .padding(.bottom, 4)
            VStack(spacing: 0) {
                content()
            }
            .background(Color.sunSurface)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private func filterRow(
        label: String,
        icon: String? = nil,
        color: Color,
        isOn: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(.caption, design: .serif))
                        .foregroundStyle(color)
                        .frame(width: 20)
                } else {
                    Circle()
                        .fill(color)
                        .frame(width: 10, height: 10)
                        .frame(width: 20)
                }
                Text(label)
                    .font(.system(.subheadline, design: .serif))
                    .foregroundStyle(Color.sunText)
                Spacer()
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold, design: .serif))
                        .foregroundStyle(Color.sunAccent)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.05))
                .frame(height: 1)
        }
    }
}
