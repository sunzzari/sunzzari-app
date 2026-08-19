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

    // A definite 16:9 frame FIRST, artwork layered onto it.
    //
    // This view used to be a ZStack whose first child was a GeometryReader, with
    // .aspectRatio(16/9, .fit) applied at the end. GeometryReader has no intrinsic
    // size, so the grid laid each cell out far SHORTER than the card that actually
    // got painted, and the artwork overflowed down across the cell beneath it.
    // .clipShape hides that overflow but does not move the tap frames, so the lower
    // third of every card answered for the card below it: tapping the middle or
    // bottom of Wine opened Activities (reported on device 2026-08-18, then
    // reproduced — Wine is drawn 773-1068pt but stopped accepting taps at ~960pt).
    //
    // Color.clear.aspectRatio gives the view a real 16:9 size, so the frame the
    // grid measures is the card the user actually sees.
    var body: some View {
        Color.clear
            .aspectRatio(16 / 9, contentMode: .fit)
            // Artwork is clipped BEFORE the labels go on. A .scaledToFill image
            // overflows its frame, and if it shares a ZStack with the labels it
            // drags the stack's bounds along — that hid the Activities title.
            .overlay { artwork }
            .clipped()
            .overlay(alignment: .bottomLeading) {
                ZStack(alignment: .bottomLeading) {
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
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            // Hit area == the drawn card.
            .contentShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var artwork: some View {
        if let assetName {
            Image(assetName)
                .resizable()
                .scaledToFill()
        } else if let urlStr = coverURL, let url = URL(string: urlStr) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure, .empty:
                    symbolTile
                @unknown default:
                    symbolTile
                }
            }
        } else {
            symbolTile
        }
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

#Preview {
    VStack(spacing: 16) {
        HubCardView(title: "Restaurants", subtitle: "My Guide", coverURL: nil)
        HubCardView(title: "Wine", subtitle: "My Collection", coverURL: nil)
    }
    .padding()
    .background(Color.sunBackground)
}
