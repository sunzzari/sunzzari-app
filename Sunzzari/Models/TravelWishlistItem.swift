import Foundation

/// One destination on the shared travel wishlist.
///
/// The month grid is the reason this model is not just a name and a checkbox:
/// Elisa's list mixes places that are only worth going at one time of year
/// (Harbin's ice festival, Strasbourg's Christmas markets) with year-round ones,
/// and that difference is invisible on a plain list.
struct TravelWishlistItem: Identifiable {
    let id: String
    var name: String
    var region: String
    var season: [String]
    var beenThere: Bool
    var notes: String
    var timingNotes: String
    /// 12 slots, January first. `nil` means the month has not been researched,
    /// which is deliberately distinct from a month rated `.avoid`.
    var monthRatings: [MonthRating?]

    enum MonthRating: String, CaseIterable {
        case best     = "Best"
        case good     = "Good"
        case shoulder = "Shoulder"
        case avoid    = "Avoid"

        var colorHex: String {
            switch self {
            case .best:     return "#70C17C"
            case .good:     return "#54A0FF"
            case .shoulder: return "#FBBF24"
            case .avoid:    return "#FF6B6B"
            }
        }
    }

    static let monthNames = ["January", "February", "March", "April", "May", "June",
                             "July", "August", "September", "October", "November", "December"]
    static let monthAbbr  = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                             "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    static let regionOptions = ["Europe", "Asia", "North America", "Latin America",
                                "Caribbean", "Africa & Middle East", "Oceania"]

    /// The `Best` months as compact ranges, e.g. "Nov-Apr" or "May, Sep-Oct".
    ///
    /// Wraps around the year end on purpose: a Maldives dry season reading
    /// "Jan-Apr, Nov-Dec" is the same fact as "Nov-Apr" and much harder to read.
    /// Empty string when nothing has been researched yet, so the caller can
    /// distinguish "no good months" from "not looked at".
    var bestMonthsSummary: String {
        let best = monthRatings.enumerated().filter { $0.element == .best }.map(\.offset)
        guard !best.isEmpty else { return "" }
        if best.count == 12 { return "Year-round" }

        let isBest = Set(best)
        // Start at a month whose predecessor is not Best, so a wrapping run is
        // walked as one range instead of being split at January.
        guard let start = (0..<12).first(where: { isBest.contains($0) && !isBest.contains(($0 + 11) % 12) })
        else { return "Year-round" }

        var ranges: [String] = []
        var i = 0
        while i < 12 {
            let m = (start + i) % 12
            guard isBest.contains(m) else { i += 1; continue }
            var length = 1
            while length < 12, isBest.contains((m + length) % 12) { length += 1 }
            let end = (m + length - 1) % 12
            ranges.append(length == 1 ? Self.monthAbbr[m]
                                      : "\(Self.monthAbbr[m])-\(Self.monthAbbr[end])")
            i += length
        }
        return ranges.joined(separator: ", ")
    }
}
