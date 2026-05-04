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
    @State private var showShareSheet = false

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private var visibleDays: [DayBundle] {
        days.filter { selectedDates.contains($0.dateString) }
            .sorted { $0.dateString < $1.dateString }
    }

    var body: some View {
        VStack(spacing: 0) {
            if !days.isEmpty {
                MultiDayPicker(days: days, selectedDates: $selectedDates)
                    .background(Color.sunSurface)
            }

            ScrollView {
                LazyVStack(spacing: 16) {
                    if visibleDays.isEmpty {
                        Text("Select a day above")
                            .font(.system(.subheadline, design: .serif))
                            .foregroundStyle(Color.sunSecondary)
                            .padding(48)
                    } else {
                        ForEach(visibleDays) { day in
                            ReadDaySection(
                                day: day,
                                selectedID: selectedID,
                                onSelect: onSelect
                            )
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 16)
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
        .onAppear {
            if selectedDates.isEmpty, let initial = pickInitialDate() {
                selectedDates = [initial]
            }
        }
        .onChange(of: selectedID) { _, newID in
            // If user tapped a marker for a day not currently selected,
            // add that day to the selection so the item is visible.
            if let id = newID, let day = day(containing: id), !selectedDates.contains(day.dateString) {
                selectedDates.insert(day.dateString)
            }
        }
    }

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

        for day in visibleDays {
            lines.append(header.string(from: day.date))
            lines.append(String(repeating: "-", count: 30))
            if !day.confirmed.isEmpty {
                lines.append("Confirmed:")
                for item in day.confirmed {
                    lines.append("  • \(item.name)" + (item.venue.isEmpty ? "" : " — \(item.venue)"))
                }
            }
            if !day.possibilities.isEmpty {
                lines.append("Could fit in:")
                for item in day.possibilities {
                    let status = item.status?.rawValue ?? ""
                    lines.append("  • \(item.name)" + (status.isEmpty ? "" : " (\(status))"))
                }
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
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
