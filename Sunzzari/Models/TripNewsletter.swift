import Foundation

/// One day's newsletter prose, sourced from the Notion Trip Newsletters DB.
/// The body lives in the Notion page's content blocks (paragraph blocks
/// joined with `\n\n`); the rest are properties on the row.
struct TripNewsletter: Identifiable, Codable {
    let id: String
    let tripId: String
    let date: String              // yyyy-MM-dd
    var prose: String             // multi-paragraph, \n\n separated
    var generatedAt: String?
    var stale: Bool
    var itemsHash: String

    /// Notion database ID for the Trip Newsletters DB. This is the page-level
    /// database ID used by /v1/databases/{id}/query in the REST API. The
    /// collection/data-source ID (3bc97d67-...) used by MCP tools is a
    /// different identifier and does NOT work with the REST API.
    static let databaseID = "ecb29b52-040e-4765-aa39-a12f22b25472"
}
