import Foundation

enum SunzzariPerson: String {
    case branch      = "Branch"
    case hummingbird = "Hummingbird"
}

struct AppIdentity {
    static let udKey = "sunzzari_identity"

    static var current: SunzzariPerson? {
        get { UserDefaults.standard.string(forKey: udKey).flatMap(SunzzariPerson.init) }
        set { UserDefaults.standard.set(newValue?.rawValue, forKey: udKey) }
    }

    static var isBranch: Bool      { current == .branch }
    static var isHummingbird: Bool { current == .hummingbird }
}
