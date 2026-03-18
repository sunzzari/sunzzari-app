import Foundation

struct Activity: Identifiable, Codable {
    let id: String
    var name: String
    var location: String
    var dateSpecific: Bool
    var dateActive: Date?
    var active: Bool
    var seasonal: Bool
    var home: Bool
    var calendarSynced: Bool
}
