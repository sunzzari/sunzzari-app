import SwiftUI
import MapKit
import CoreLocation
import UIKit

struct DayDetailView: View {
    let trip: Trip
    let days: [DayBundle]
    @Binding var selectedID: String?
    let userLocation: CLLocation?
    let onSelect: (TripItem) -> Void

    @State private var selectedDates: Set<String> = []
    @State private var activeTypes: Set<TripItem.ItemType> = []
    @State private var bridge = TripMapBridge()
    @State private var showShareSheet = false
    @State private var showMap = true
    @State private var detailItem: TripItem?

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private var visibleDays: [DayBundle] {
        days.filter { selectedDates.contains($0.dateString) }
            .sorted { $0.dateString < $1.dateString }
    }

    /// Union of all visible-day items, filtered by activeTypes (legend).
    private var sharedItems: [TripItem] {
        let all = visibleDays.flatMap(\.allItems)
        if activeTypes.isEmpty { return all }
        return all.filter { item in
            guard let t = item.type else { return false }
            return activeTypes.contains(t)
        }
    }

    private var sharedAnnotations: [TripItemAnnotation] {
        sharedItems.compactMap { item in
            guard let lat = item.latitude, let lon = item.longitude else { return nil }
            return TripItemAnnotation(
                item: item,
                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon)
            )
        }
    }

    /// Polyline only when EXACTLY ONE day is selected. Multi-day = no polyline,
    /// matching web parity (web has no polyline at all in any mode).
    private var routeAnnotations: [TripItemAnnotation] {
        guard visibleDays.count == 1, let only = visibleDays.first else { return [] }
        return only.confirmed.compactMap { item in
            guard let lat = item.latitude, let lon = item.longitude else { return nil }
            return TripItemAnnotation(
                item: item,
                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon)
            )
        }
    }

    private var filterKey: String {
        "days-\(selectedDates.sorted().joined(separator: ","))-types-\(activeTypes.map(\.rawValue).sorted().joined(separator: ","))"
    }

    var body: some View {
        VStack(spacing: 0) {
            if !days.isEmpty {
                MultiDayPicker(days: days, selectedDates: $selectedDates)
                    .background(Color.sunSurface)
            }

            mapToggleBar

            if showMap {
                sharedMap
                    .frame(height: 280)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            ScrollView {
                LazyVStack(spacing: 14) {
                    if visibleDays.isEmpty {
                        Text("Select a day above")
                            .font(.system(.subheadline, design: .serif))
                            .foregroundStyle(Color.sunSecondary)
                            .padding(48)
                    } else {
                        ForEach(visibleDays) { day in
                            NewsletterDayCard(
                                day: day,
                                selectedID: selectedID,
                                onSelect: handleRowTap
                            )
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 14)
            }
        }
        .background(Color.sunBackground)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showShareSheet = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(.body, design: .serif))
                        .foregroundStyle(Color.sunText)
                }
                .disabled(visibleDays.isEmpty)
            }
        }
        .sheet(isPresented: $showShareSheet) {
            DayShareSheet(text: buildShareText())
        }
        .sheet(item: $detailItem) { item in
            ItemDetailSheet(item: item, userLocation: userLocation)
        }
        .onAppear {
            if selectedDates.isEmpty, let initial = pickInitialDate() {
                selectedDates = [initial]
            }
        }
        .onChange(of: selectedID) { _, newID in
            // If user tapped a marker for a day not currently selected, add
            // that day to the selection so the item appears in the prose stack.
            if let id = newID, let day = day(containing: id), !selectedDates.contains(day.dateString) {
                selectedDates.insert(day.dateString)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: showMap)
    }

    private var mapToggleBar: some View {
        HStack(spacing: 10) {
            Button {
                showMap.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: showMap ? "map.fill" : "map")
                    Text(showMap ? "Hide map" : "Show map")
                }
                .font(.system(.caption2, design: .serif, weight: .medium))
                .foregroundStyle(Color.sunText)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.sunSurface))
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.sunSurface.opacity(0.5))
    }

    /// Row-tap handler used by NewsletterDayCard. Sets selectedID (which
    /// drives the shared map's selection halo + auto-pan via selectAnnotation),
    /// pans the day's bridge as a belt-and-suspenders fallback, and on a
    /// repeat tap opens ItemDetailSheet (matches the marker-tap two-step).
    private func handleRowTap(_ item: TripItem) {
        if let lat = item.latitude, let lon = item.longitude {
            DispatchQueue.main.async {
                bridge.panTo(CLLocationCoordinate2D(latitude: lat, longitude: lon))
            }
        }
        if selectedID == item.id {
            detailItem = item
        } else {
            selectedID = item.id
        }
    }

    // MARK: - Shared map

    private var sharedMap: some View {
        ZStack {
            TripMKMap(
                annotations: sharedAnnotations,
                filterKey: filterKey,
                selectedID: mapSelectionBinding,
                bridge: bridge,
                routeAnnotations: routeAnnotations,
                interactive: true,
                alwaysAutoFit: true,
                onOpenDetail: { item in detailItem = item }
            )

            // Map controls
            VStack(spacing: 8) {
                mapButton(icon: "arrow.up.left.and.down.right.magnifyingglass") {
                    bridge.fitAll()
                }
                mapButton(icon: "location.fill") {
                    bridge.centerOnUser()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .padding(12)

            // Compact type legend (bottom-leading). Designed to fit a 280pt
            // map without blocking the markers: collapsed by default to a
            // single chip showing active count; tap to expand.
            CompactTypeLegend(activeTypes: $activeTypes)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(.leading, 12)
                .padding(.bottom, 12)
        }
    }

    /// Marker tap routes through onSelect (handled by parent) and also
    /// updates the local selectedID via the parent's binding.
    private var mapSelectionBinding: Binding<String?> {
        Binding(
            get: { selectedID },
            set: { newID in
                if let id = newID, let item = sharedItems.first(where: { $0.id == id }) {
                    onSelect(item)
                } else {
                    selectedID = nil
                }
            }
        )
    }

    private func mapButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(.caption, design: .serif))
                .foregroundStyle(Color.sunText)
                .frame(width: 36, height: 36)
                .background(Color.sunSurface.opacity(0.9))
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.2), radius: 2)
        }
    }

    // MARK: - Helpers

    private func pickInitialDate() -> String? {
        let today = Self.formatter.string(from: Date())
        if days.contains(where: { $0.dateString == today }) { return today }
        return days.first?.dateString
    }

    private func day(containing itemID: String) -> DayBundle? {
        days.first { d in d.allItems.contains(where: { $0.id == itemID }) }
    }

    private func buildShareText() -> String {
        var lines: [String] = []
        lines.append(trip.name)
        lines.append(String(repeating: "=", count: trip.name.count))
        lines.append("")

        let header = DateFormatter()
        header.dateFormat = "EEEE, MMMM d"
        header.timeZone = TimeZone(identifier: "UTC")

        for day in visibleDays {
            lines.append("NEWSLETTER")
            lines.append(header.string(from: day.date))
            lines.append(String(repeating: "-", count: 30))

            let narrative = DayNarrativeService.narrative(for: day)
            if !narrative.isEmpty {
                lines.append(narrative.joined)
                lines.append("")
            }
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Compact type legend

/// Collapsed-by-default type filter for the Day-mode shared map. A single
/// pill shows "Types" + active count; tap to expand a horizontal chip strip
/// with all types. Designed to coexist with a 280pt map without covering
/// the markers (the original `TripTypeLegend` is ~290pt tall in column form).
private struct CompactTypeLegend: View {
    @Binding var activeTypes: Set<TripItem.ItemType>
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if expanded {
                expandedStrip
            }
            collapsedPill
        }
    }

    private var collapsedPill: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal.decrease.circle\(activeTypes.isEmpty ? "" : ".fill")")
                    .font(.system(.caption, design: .serif))
                Text(activeTypes.isEmpty ? "Filter" : "Filter (\(activeTypes.count))")
                    .font(.system(.caption2, design: .serif, weight: .medium))
            }
            .foregroundStyle(Color.sunText)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial)
            .environment(\.colorScheme, .dark)
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.3), radius: 4)
        }
        .buttonStyle(.plain)
    }

    private var expandedStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(TripItem.ItemType.allCases, id: \.self) { type in
                    chip(for: type)
                }
                if !activeTypes.isEmpty {
                    Button {
                        activeTypes.removeAll()
                    } label: {
                        Text("Clear")
                            .font(.system(.caption2, design: .serif))
                            .underline()
                            .foregroundStyle(Color.sunAccent)
                            .padding(.horizontal, 6)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .frame(maxWidth: 320)
        .background(.ultraThinMaterial)
        .environment(\.colorScheme, .dark)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.3), radius: 4)
    }

    private func chip(for type: TripItem.ItemType) -> some View {
        let isActive = activeTypes.contains(type)
        return Button {
            if isActive { activeTypes.remove(type) }
            else { activeTypes.insert(type) }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: type.sfSymbol)
                    .font(.system(size: 9, design: .serif))
                    .foregroundStyle(.white)
                    .frame(width: 16, height: 16)
                    .background(Circle().fill(type.color))
                if isActive {
                    Text(type.rawValue)
                        .font(.system(.caption2, design: .serif, weight: .medium))
                        .foregroundStyle(Color.sunText)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(isActive ? type.color.opacity(0.25) : Color.clear)
            )
            .overlay(
                Capsule().stroke(isActive ? type.color : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Multi-day picker

private struct MultiDayPicker: View {
    let days: [DayBundle]
    @Binding var selectedDates: Set<String>

    private static let chipFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(days) { day in
                    chip(for: day)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }

    @ViewBuilder
    private func chip(for day: DayBundle) -> some View {
        let isSelected = selectedDates.contains(day.dateString)
        Button {
            if isSelected {
                if selectedDates.count > 1 {
                    selectedDates.remove(day.dateString)
                }
            } else {
                selectedDates.insert(day.dateString)
            }
        } label: {
            VStack(spacing: 2) {
                Text(Self.weekdayFormatter.string(from: day.date))
                    .font(.system(.caption2, design: .serif))
                Text(Self.chipFormatter.string(from: day.date))
                    .font(.system(.caption, design: .serif, weight: .semibold))
            }
            .foregroundStyle(isSelected ? Color.sunBackground : Color.sunText)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(isSelected ? Color.sunAccent : Color.sunSurface.opacity(0.4))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Share sheet

private struct DayShareSheet: UIViewControllerRepresentable {
    let text: String

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [text], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
