import SwiftUI

/// Per-day prose card. Stacked in a ScrollView inside `DayDetailView`, one
/// per selected day. The shared interactive map lives ABOVE this card stack
/// (in `DayDetailView`).
///
/// Body composition (top to bottom):
///   1. Header (NEWSLETTER pill + day-of-week + date)
///   2. Multi-paragraph narrative from `DayNarrativeService`
///   3. Compact items strip below (tappable rows that highlight on the map
///      and open `ItemDetailSheet` on second tap)
///
/// No embedded mini-map.
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

    private var narrative: DayNarrative {
        DayNarrativeService.narrative(for: day)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            // Multi-paragraph narrative body. Each non-nil section becomes
            // its own line-wrapped Text with vertical breathing room.
            VStack(alignment: .leading, spacing: 12) {
                if let intro = narrative.intro {
                    paragraph(intro)
                }
                if let confirmed = narrative.confirmedParagraph {
                    paragraph(confirmed)
                }
                if let possibilities = narrative.possibilitiesParagraph {
                    paragraph(possibilities)
                }
                if let closing = narrative.closing {
                    paragraph(closing)
                }
            }

            if !day.allItems.isEmpty {
                itemsStrip
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.sunSurface.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("NEWSLETTER")
                .font(.system(.caption, design: .serif, weight: .bold))
                .foregroundStyle(Color.sunBackground)
                .tracking(2.0)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.sunAccent))
            Text(Self.displayHeader.string(from: day.date))
                .font(.system(.title3, design: .serif, weight: .semibold))
                .foregroundStyle(Color.sunText)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Paragraph

    private func paragraph(_ text: String) -> some View {
        Text(text)
            .font(.system(.body, design: .serif))
            .foregroundStyle(Color.sunText.opacity(0.9))
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Items strip

    /// Compact list of all the day's items. Each row is one line: status
    /// dot + name (+ time prefix if available). Tapping routes through
    /// `onSelect(item)` so the shared map highlights the marker and a
    /// repeat tap opens `ItemDetailSheet`.
    private var itemsStrip: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("ITEMS")
                .font(.system(.caption2, design: .serif, weight: .semibold))
                .foregroundStyle(Color.sunSecondary)
                .tracking(1.0)
                .padding(.bottom, 6)

            ForEach(day.allItems) { item in
                itemRow(item, isPossibility: !day.confirmed.contains(where: { $0.id == item.id }))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.sunBackground.opacity(0.5))
        )
    }

    private func itemRow(_ item: TripItem, isPossibility: Bool) -> some View {
        Button { onSelect(item) } label: {
            HStack(spacing: 8) {
                statusDot(for: item, hollow: isPossibility)

                if let timeStr = DayNarrativeService.formattedTime(for: item) {
                    Text(timeStr)
                        .font(.system(.caption, design: .serif, weight: .medium))
                        .foregroundStyle(Color.sunSecondary)
                        .frame(width: 56, alignment: .leading)
                }

                Text(item.name)
                    .font(.system(.subheadline, design: .serif))
                    .foregroundStyle(Color.sunText)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.vertical, 5)
            .background(selectedID == item.id ? Color.sunAccent.opacity(0.15) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 5))
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
}
