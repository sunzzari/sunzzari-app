import SwiftUI

struct WineCardView: View {
    let wine: Wine

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(Color(hex: wine.wineType.colorHex))
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top) {
                    Text(wine.wineName)
                        .font(.system(size: 15, weight: .bold, design: .serif))
                        .fontDesign(.serif)
                        .foregroundStyle(Color.sunText)
                        .lineLimit(2)

                    Spacer()

                    // Rating stars on right
                    if let rating = wine.rating {
                        Text(rating.rawValue)
                            .font(.system(size: 12, design: .serif))
                    }
                }

                // Producer · Vintage
                let producerVintage = [
                    wine.producer.isEmpty ? nil : wine.producer,
                    wine.vintage.map { String($0) }
                ].compactMap { $0 }.joined(separator: " · ")
                if !producerVintage.isEmpty {
                    Text(producerVintage)
                        .font(.subheadline)
                        .foregroundStyle(Color.sunSecondary)
                }

                HStack(spacing: 6) {
                    // Wine type chip
                    Text(wine.wineType.rawValue.uppercased())
                        .font(.system(size: 9, weight: .bold, design: .serif))
                        .tracking(0.5)
                        .foregroundStyle(Color(hex: wine.wineType.colorHex))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color(hex: wine.wineType.colorHex).opacity(0.18))
                        .clipShape(RoundedRectangle(cornerRadius: 4))

                    // Region
                    if !wine.region.isEmpty {
                        Text(wine.region)
                            .font(.caption)
                            .foregroundStyle(Color.sunSecondary)
                    }

                    if wine.useForCooking {
                        Text("COOKING")
                            .font(.system(size: 9, weight: .bold, design: .serif))
                            .tracking(0.5)
                            .foregroundStyle(Color.sunAccent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.sunAccent.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 12)
        }
        .background(Color.sunBackground)
    }
}
