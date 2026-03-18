import SwiftUI

struct HubCardView: View {
    let title: String
    let subtitle: String
    let coverURL: String?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            GeometryReader { geo in
                if let urlStr = coverURL, let url = URL(string: urlStr) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: geo.size.width, height: geo.size.height)
                                .clipped()
                        case .failure, .empty:
                            placeholder
                                .frame(width: geo.size.width, height: geo.size.height)
                        @unknown default:
                            placeholder
                                .frame(width: geo.size.width, height: geo.size.height)
                        }
                    }
                } else {
                    placeholder
                        .frame(width: geo.size.width, height: geo.size.height)
                }
            }

            LinearGradient(
                colors: [.black.opacity(0.75), .black.opacity(0.05)],
                startPoint: .bottom, endPoint: .top
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(subtitle)
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(.white.opacity(0.7))
                Text(title)
                    .font(.system(size: 28, weight: .bold))
                    .fontDesign(.serif)
                    .foregroundStyle(.white)
            }
            .padding(20)
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var placeholder: some View {
        LinearGradient(
            colors: [Color.sunSurface, Color(hex: "#374151")],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }
}
