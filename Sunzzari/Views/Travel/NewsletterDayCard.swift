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
    /// When non-nil, this Notion-sourced prose replaces the local
    /// DayNarrativeService output. Multiple paragraphs separated by `\n\n`.
    var notionProse: String? = nil

    private static let displayHeader: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d"
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    /// Body paragraphs to render. Prefers the Notion prose when set; falls back
    /// to the local generator's per-section narrative.
    private var paragraphs: [String] {
        if let prose = notionProse, !prose.isEmpty {
            return prose.components(separatedBy: "\n\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        let n = DayNarrativeService.narrative(for: day)
        return [n.intro, n.confirmedParagraph, n.possibilitiesParagraph, n.closing].compactMap { $0 }
    }

    /// Confirmed/Assigned anchors for the day, time-sorted when times exist.
    private var confirmedDisplayItems: [TripItem] {
        day.confirmed.sorted { lhs, rhs in
            let lt = DayNarrativeService.formattedTime(for: lhs)
            let rt = DayNarrativeService.formattedTime(for: rhs)
            if lt != nil && rt == nil { return true }
            if lt == nil && rt != nil { return false }
            return (lhs.displayDate ?? "") < (rhs.displayDate ?? "")
        }
    }

    /// Pool items the newsletter actually picked (name appears in prose).
    /// Deduped against confirmed names so the same place doesn't appear twice
    /// when the user has both a Confirmed and a Researching entry sharing a
    /// name (e.g. two "Le Tout-Paris" rows in the Notion DB).
    /// When there's no Notion prose, fall back to all possibilities.
    private var poolDisplayItems: [TripItem] {
        let confirmedNames = Set(day.confirmed.map { $0.name.lowercased() })
        let confirmedIDs = Set(day.confirmed.map(\.id))
        let basePool = day.possibilities.filter { item in
            !confirmedIDs.contains(item.id) &&
            !confirmedNames.contains(item.name.lowercased())
        }
        guard let prose = notionProse, !prose.isEmpty else {
            return basePool
        }
        return basePool.filter { item in
            !item.name.isEmpty && prose.localizedCaseInsensitiveContains(item.name)
        }
    }

    private var hasAnyDisplayItems: Bool {
        !confirmedDisplayItems.isEmpty || !poolDisplayItems.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, p in
                    paragraph(p)
                }
            }

            if hasAnyDisplayItems {
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

    /// Items strip below the prose. Two sections: confirmed anchors (with
    /// times, time-sorted) and possibilities the newsletter picked (name
    /// only, no time). Tapping any row routes through `onSelect(item)` so
    /// the shared map pans + highlights, repeat tap opens `ItemDetailSheet`.
    private var itemsStrip: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !confirmedDisplayItems.isEmpty {
                sectionHeader("CONFIRMED")
                ForEach(confirmedDisplayItems) { item in
                    confirmedRow(item)
                }
            }
            if !poolDisplayItems.isEmpty {
                sectionHeader("POSSIBILITIES")
                    .padding(.top, confirmedDisplayItems.isEmpty ? 0 : 10)
                ForEach(poolDisplayItems) { item in
                    poolRow(item)
                }
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

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(.caption2, design: .serif, weight: .semibold))
            .foregroundStyle(Color.sunSecondary)
            .tracking(1.0)
            .padding(.bottom, 6)
    }

    /// Confirmed/Assigned row. Reserves a 56pt time column even when the
    /// item has no time set, so all confirmed rows align cleanly. Time text
    /// is rendered only when the Notion `Assigned to Date` carries a time.
    private func confirmedRow(_ item: TripItem) -> some View {
        Button { onSelect(item) } label: {
            HStack(spacing: 8) {
                statusDot(for: item, hollow: false)
                Text(DayNarrativeService.formattedTime(for: item) ?? "")
                    .font(.system(.caption, design: .serif, weight: .medium))
                    .foregroundStyle(Color.sunSecondary)
                    .frame(width: 56, alignment: .leading)
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

    /// Pool row. Hollow dot, no time column, name only.
    private func poolRow(_ item: TripItem) -> some View {
        Button { onSelect(item) } label: {
            HStack(spacing: 8) {
                statusDot(for: item, hollow: true)
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
