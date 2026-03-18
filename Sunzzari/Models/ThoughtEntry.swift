import Foundation

struct ThoughtEntry: Identifiable {
    let id: String
    let content: String
    let author: String   // "Hummingbird" or "Branch"
    let date: Date       // parsed from Notion created_time

    var authorEmoji: String {
        author == "Hummingbird" ? "🕊️" : "🌿"
    }

    var authorColorHex: String {
        author == "Hummingbird" ? "#38BDF8" : "#4ADE80"
    }
}
