import Foundation
import UIKit

final class CloudinaryService: @unchecked Sendable {
    static let shared = CloudinaryService()

    func upload(image: UIImage, maxDimension: CGFloat = 1200) async throws -> String {
        guard let compressed = compress(image, maxDimension: maxDimension, quality: 0.82) else {
            throw CloudinaryError.compressionFailed
        }
        let json = try await postUpload(imageData: compressed, folder: nil, filename: "dino.jpg")
        guard let secureURL = json["secure_url"] as? String else {
            throw CloudinaryError.invalidResponse
        }
        return secureURL
    }

    /// Story upload: stores in the `stories` folder and returns the Cloudinary
    /// `public_id` so the client can derive transform URLs (low-res for the
    /// archive grid, full-res for the player) without baking a fixed transform
    /// into the persisted record.
    func uploadStory(image: UIImage, maxDimension: CGFloat = 1920) async throws -> String {
        guard let compressed = compress(image, maxDimension: maxDimension, quality: 0.80) else {
            throw CloudinaryError.compressionFailed
        }
        let json = try await postUpload(imageData: compressed, folder: "stories", filename: "story.jpg")
        guard let publicID = json["public_id"] as? String else {
            throw CloudinaryError.invalidResponse
        }
        return publicID
    }

    // MARK: - Private

    private func postUpload(imageData: Data, folder: String?, filename: String) async throws -> [String: Any] {
        let url = URL(string: "https://api.cloudinary.com/v1_1/\(Constants.Cloudinary.cloudName)/image/upload")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = buildMultipartBody(imageData: imageData, boundary: boundary, folder: folder, filename: filename)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw CloudinaryError.uploadFailed
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CloudinaryError.invalidResponse
        }
        return json
    }

    private func compress(_ image: UIImage, maxDimension: CGFloat, quality: CGFloat) -> Data? {
        let size = image.size
        let scale = min(maxDimension / size.width, maxDimension / size.height, 1.0)
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
        return resized.jpegData(compressionQuality: quality)
    }

    private func buildMultipartBody(imageData: Data, boundary: String, folder: String?, filename: String) -> Data {
        var body = Data()
        let nl = "\r\n"

        func append(_ string: String) { body.append(Data(string.utf8)) }

        append("--\(boundary)\(nl)")
        append("Content-Disposition: form-data; name=\"upload_preset\"\(nl)\(nl)")
        append("\(Constants.Cloudinary.uploadPreset)\(nl)")

        if let folder {
            append("--\(boundary)\(nl)")
            append("Content-Disposition: form-data; name=\"folder\"\(nl)\(nl)")
            append("\(folder)\(nl)")
        }

        append("--\(boundary)\(nl)")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\(nl)")
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
