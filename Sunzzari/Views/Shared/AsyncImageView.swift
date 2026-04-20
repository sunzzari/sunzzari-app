import SwiftUI

struct AsyncImageView: View {
    let urlString: String?
    var cornerRadius: CGFloat = 12
    // When set, Cloudinary URLs are rewritten to request a thumbnail of this width.
    // Full-res viewers (e.g. DinoDetailView) should leave this nil.
    var thumbnailWidth: Int? = nil

    var body: some View {
        if let urlString, let url = resolvedURL(from: urlString) {
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

    private func resolvedURL(from string: String) -> URL? {
        guard let width = thumbnailWidth,
              let range = string.range(of: "/upload/"),
              !string.contains("/upload/f_auto") else {
            return URL(string: string)
        }
        let transform = "f_auto,q_auto,w_\(width)/"
        let rewritten = string.replacingCharacters(in: range, with: "/upload/\(transform)")
        return URL(string: rewritten)
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
