import Foundation

struct TripAssistantResponse: Codable {
    let answer: String
    let matchedItemIds: [String]
    let suggestions: [ExternalSuggestion]

    struct ExternalSuggestion: Codable {
        let name: String
        let type: String
        let neighborhood: String
        let reason: String
    }
}
