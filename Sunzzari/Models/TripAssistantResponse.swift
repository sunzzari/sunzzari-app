import Foundation

struct TripAssistantResponse: Codable, Equatable {
    let answer: String
    let matchedItemIds: [String]
    let suggestions: [ExternalSuggestion]

    struct ExternalSuggestion: Codable, Equatable {
        let name: String
        let type: String
        let neighborhood: String
        let reason: String
    }
}
