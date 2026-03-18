import Foundation

struct CycleEntry: Identifiable, Codable {
    let id: String
    var periodStart: Date
    var person: Person
    var avgCycle: Int
    var notes: String
    var predictedNext: Date?
    var cycleLength: Int?

    enum Person: String, CaseIterable, Codable {
        case elisa = "Elisa"
        case cathy = "Cathy"

        var colorHex: String {
            switch self {
            case .elisa: return "#F472B6"
            case .cathy: return "#A78BFA"
            }
        }

        var fadedColorHex: String {
            switch self {
            case .elisa: return "#F472B640"
            case .cathy: return "#A78BFA40"
            }
        }
    }
}
