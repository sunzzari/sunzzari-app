import SwiftUI

struct AsyncImageView: View {
    let urlString: String?
    var cornerRadius: CGFloat = 12

    var body: some View {
        if let urlString, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    Rectangle()
                        .fill(Color.sunSurface)
                        .overlay(ProgressView().tint(.sunSecondary))
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .clipped()
                case .failure:
                    placeholderView
                @unknown default:
                    placeholderView
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            placeholderView
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        }
    }

    private var placeholderView: some View {
        Rectangle()
            .fill(Color.sunSurface)
            .overlay(
                Image(systemName: "photo")
                    .font(.title2)
                    .foregroundStyle(Color.sunSecondary)
            )
    }
}
