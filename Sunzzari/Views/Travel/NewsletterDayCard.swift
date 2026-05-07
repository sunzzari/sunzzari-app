import SwiftUI

/// Per-day prose card. Stacked in a ScrollView inside `DayDetailView`, one
/// per selected day. The shared interactive map lives ABOVE this card stack
/// (in `DayDetailView`), so this card is pure prose: header + narrative
/// intro + Confirmed bullet list + Could fit bullet list. No embedded map.
struct NewsletterDayCard: View {

    let day: DayBundle
    let selectedID: String?
    let onSelect: (TripItem) -> Void

    private static let displayHeader: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d"
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            VStack(alignment: .leading, spacing: 2) {
                Text("NEWSLETTER")
                    .font(.system(.caption2, design: .serif, weight: .semibold))
                    .foregroundStyle(Color.sunAccent)
                    .tracking(1.5)
                Text(Self.displayHeader.string(from: day.date))
                    .font(.system(.title3, design: .serif, weight: .semibold))
                    .foregroundStyle(Color.sunText)
            }

            // Narrative intro (1-2 sentences)
            if let narrative = DayNarrativeService.narrative(for: day) {
                Text(narrative)
                    .font(.system(.subheadline, design: .serif))
                    .foregroundStyle(Color.sunText.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Confirmed plan
            if !day.confirmed.isEmpty {
                sectionHeader("Confirmed plan")
                ForEach(day.confirmed) { item in
                    proseRow(for: item, isPossibility: false)
                }
            }

            // Could fit in
            if !day.possibilities.isEmpty {
                sectionHeader("Could fit in")
                ForEach(day.possibilities) { item in
                    proseRow(for: item, isPossibility: true)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.sunSurface.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(.caption, design: .serif, weight: .semibold))
            .foregroundStyle(Color.sunSecondary)
            .tracking(0.6)
            .padding(.top, 4)
    }

    @ViewBuilder
    private func proseRow(for item: TripItem, isPossibility: Bool) -> some View {
        Button { onSelect(item) } label: {
            HStack(alignment: .top, spacing: 10) {
                statusDot(for: item, hollow: isPossibility)
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

    @ViewBuilder
    private func statusDot(for item: TripItem, hollow: Bool) -> some View {
        let color = item.status?.color ?? Color.sunSecondary
        if hollow {
            Circle()
                .stroke(color, lineWidth: 1.2)
                .frame(width: 7, height: 7)
        } else {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
        }
    }

    private func proseTitle(for item: TripItem) -> String {
        var parts: [String] = []
        if let timeStr = DayNarrativeService.formattedTime(for: item) {
            parts.append(timeStr)
        }
        switch item.type {
        case .hotel:     parts.append("Stay:")
        case .carRental: parts.append("Pickup:")
        default:         break
        }
        parts.append(item.name)
        let head = parts.joined(separator: " ")
        return item.venue.isEmpty ? head : "\(head) — \(item.venue)"
    }
}
