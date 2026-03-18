import SwiftUI

struct ActivityCardView: View {
    let activity: Activity

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f
    }()

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(activity.active ? Color.sunAccent : Color.sunSecondary.opacity(0.4))
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top) {
                    Text(activity.name)
                        .font(.system(size: 15, weight: .bold))
                        .fontDesign(.serif)
                        .foregroundStyle(Color.sunText)
                        .lineLimit(2)
                    Spacer()
                }

                if !activity.location.isEmpty {
                    Text(activity.location)
                        .font(.subheadline)
                        .foregroundStyle(Color.sunSecondary)
                }

                if activity.dateSpecific, let date = activity.dateActive {
                    Text(dateFormatter.string(from: date))
                        .font(.caption)
                        .foregroundStyle(Color.sunAccent)
                }

                // Status badges
                let badges: [(String, String)] = [
                    activity.active ? ("ACTIVE", "#70C17C") : nil,
                    activity.seasonal ? ("SEASONAL", "#60A5FA") : nil,
                    activity.home ? ("HOME", "#F472B6") : nil,
                    activity.calendarSynced ? ("SYNCED", "#8E8E93") : nil
                ].compactMap { $0 }

                if !badges.isEmpty {
                    HStack(spacing: 5) {
                        ForEach(badges, id: \.0) { badge, hex in
                            Text(badge)
                                .font(.system(size: 9, weight: .bold))
                                .tracking(0.5)
                                .foregroundStyle(Color(hex: hex))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color(hex: hex).opacity(0.18))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 12)
        }
        .background(Color.sunBackground)
    }
}
