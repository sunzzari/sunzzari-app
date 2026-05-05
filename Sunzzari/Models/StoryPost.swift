import Foundation

struct StoryPost: Identifiable, Codable, Hashable {
    let id: String
    var publicID: String
    var caption: String
    var person: Person
    var postedAt: Date
    var location: String?

    enum Person: String, CaseIterable, Codable {
        case elisa = "Elisa"
        case cathy = "Cathy"

        var colorHex: String {
            switch self {
            case .elisa: return "#F472B6"
            case .cathy: return "#A78BFA"
            }
        }
    }

    var thumbnailURL: URL? {
        Self.cloudinaryURL(publicID: publicID, transform: "w_360,c_fill,q_auto,f_auto")
    }

    var fullURL: URL? {
        Self.cloudinaryURL(publicID: publicID, transform: "w_1080,c_fill,q_auto,f_auto")
    }

    private static func cloudinaryURL(publicID: String, transform: String) -> URL? {
        URL(string: "https://res.cloudinary.com/\(Constants.Cloudinary.cloudName)/image/upload/\(transform)/\(publicID)")
    }
}
