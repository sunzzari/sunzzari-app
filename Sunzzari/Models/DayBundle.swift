import Foundation

struct DayBundle: Identifiable, Hashable {
    let date: Date
    let dateString: String
    let confirmed: [TripItem]
    let possibilities: [TripItem]

    var id: String { dateString }

    var hasAnyItems: Bool { !confirmed.isEmpty || !possibilities.isEmpty }

    var allItems: [TripItem] { confirmed + possibilities }

    static func == (lhs: DayBundle, rhs: DayBundle) -> Bool { lhs.dateString == rhs.dateString }
    func hash(into hasher: inout Hasher) { hasher.combine(dateString) }
}
