import Foundation
import UIKit

final class CloudinaryService: @unchecked Sendable {
    static let shared = CloudinaryService()

    func upload(image: UIImage, maxDimension: CGFloat = 1200) async throws -> String {
        guard let compressed = compress(image, maxDimension: maxDimension) else {
            throw CloudinaryError.compressionFailed
        }

        let url = URL(string: "https://api.cloudinary.com/v1_1/\(Constants.Cloudinary.cloudName)/image/upload")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = buildMultipartBody(imageData: compressed, boundary: boundary)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw CloudinaryError.uploadFailed
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let secureURL = json["secure_url"] as? String else {
            throw CloudinaryError.invalidResponse
        }
        return secureURL
    }

    // MARK: - Private

    private func compress(_ image: UIImage, maxDimension: CGFloat) -> Data? {
        let size = image.size
        let scale = min(maxDimension / size.width, maxDimension / size.height, 1.0)
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
        return resized.jpegData(compressionQuality: 0.82)
    }

    private func buildMultipartBody(imageData: Data, boundary: String) -> Data {
        var body = Data()
        let nl = "\r\n"

        func append(_ string: String) { body.append(Data(string.utf8)) }

        append("--\(boundary)\(nl)")
        append("Content-Disposition: form-data; name=\"upload_preset\"\(nl)\(nl)")
        append("\(Constants.Cloudinary.uploadPreset)\(nl)")

        append("--\(boundary)\(nl)")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"dino.jpg\"\(nl)")
        append("Content-Type: image/jpeg\(nl)\(nl)")
        body.append(imageData)
        append(nl)

        append("--\(boundary)--\(nl)")
        return body
    }

    enum CloudinaryError: LocalizedError {
        case compressionFailed
        case uploadFailed
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .compressionFailed: return "Could not compress image"
            case .uploadFailed:      return "Upload to Cloudinary failed"
            case .invalidResponse:   return "Unexpected response from Cloudinary"
            }
        }
    }
}
