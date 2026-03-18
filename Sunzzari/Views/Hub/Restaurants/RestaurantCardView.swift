import SwiftUI

struct RestaurantCardView: View {
    let restaurant: Restaurant

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Left accent bar + content
            HStack(spacing: 0) {
                Rectangle()
                    .fill(restaurant.preference.map { Color(hex: $0.colorHex) } ?? Color.sunSecondary)
                    .frame(width: 3)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top) {
                        Text(restaurant.name)
                            .font(.system(size: 15, weight: .bold))
                            .fontDesign(.serif)
                            .foregroundStyle(Color.sunText)
                            .lineLimit(2)

                        Spacer()

                        if let pref = restaurant.preference {
                            Text(pref.rawValue.uppercased())
                                .font(.system(size: 9, weight: .bold))
                                .tracking(0.6)
                                .foregroundStyle(Color(hex: pref.colorHex))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color(hex: pref.colorHex).opacity(0.18))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }

                    // Location / neighborhood
                    let loc = [restaurant.location, restaurant.neighborhood]
                        .filter { !$0.isEmpty }.joined(separator: " · ")
                    if !loc.isEmpty {
                        Text(loc)
                            .font(.subheadline)
                            .foregroundStyle(Color.sunSecondary)
                    }

                    // Good For chips (max 3 + overflow)
                    if !restaurant.goodFor.isEmpty {
                        let visible = Array(restaurant.goodFor.prefix(3))
                        let overflow = restaurant.goodFor.count - visible.count
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 5) {
                                ForEach(visible, id: \.self) { tag in
                                    Text(tag.uppercased())
                                        .font(.system(size: 9, weight: .bold))
                                        .tracking(0.5)
                                        .foregroundStyle(Color.sunSecondary)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(Color.sunSurface)
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                }
                                if overflow > 0 {
                                    Text("+\(overflow) more")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(Color.sunSecondary)
                                }
                            }
                        }
                        .scrollDisabled(true)
                    }
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 12)
            }
        }
        .background(Color.sunBackground)
    }
}
