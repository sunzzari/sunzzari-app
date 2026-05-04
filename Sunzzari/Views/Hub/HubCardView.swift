import SwiftUI

struct HubCardView: View {
    let title: String
    let subtitle: String
    let assetName: String?
    let coverURL: String?
    let symbolName: String?

    init(title: String, subtitle: String, assetName: String? = nil, coverURL: String? = nil, symbolName: String? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.assetName = assetName
        self.coverURL = coverURL
        self.symbolName = symbolName
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            GeometryReader { geo in
                if let assetName {
                    Image(assetName)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                } else if let urlStr = coverURL, let url = URL(string: urlStr) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: geo.size.width, height: geo.size.height)
                                .clipped()
                        case .failure, .empty:
                            symbolTile
                                .frame(width: geo.size.width, height: geo.size.height)
                        @unknown default:
                            symbolTile
                                .frame(width: geo.size.width, height: geo.size.height)
                        }
                    }
                } else {
                    symbolTile
                        .frame(width: geo.size.width, height: geo.size.height)
                }
            }

            LinearGradient(
                colors: [.black.opacity(0.75), .black.opacity(0.05)],
                startPoint: .bottom, endPoint: .top
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(subtitle)
                    .font(.system(size: 10, weight: .semibold, design: .serif))
                    .tracking(1.0)
                    .foregroundStyle(.white.opacity(0.7))
                Text(title)
                    .font(.system(size: 20, weight: .bold, design: .serif))
                    .fontDesign(.serif)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(14)
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var symbolTile: some View {
        ZStack {
            LinearGradient(
                colors: [Color.sunSurface, Color(hex: "#374151")],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            if let symbolName {
                Image(systemName: symbolName)
                    .font(.system(size: 64, weight: .light, design: .serif))
                    .foregroundStyle(Color.sunAccent.opacity(0.85))
            }
        }
    }
}
