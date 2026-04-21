import SwiftUI

struct SwipeGuideView: View {
    @State private var personFilter: PersonFilter = .all

    enum PersonFilter { case all, elisa, cathy }

    struct SwipeRow {
        let category: String
        let elisaCard: String?
        let elisaMultiplier: String
        let cathyCard: String?
        let cathyMultiplier: String
        let note: String
    }

    let rows: [SwipeRow] = [
        SwipeRow(category: "Flights (direct to airline)",
                 elisaCard: "Amex Platinum",      elisaMultiplier: "5x",
                 cathyCard: "Chase Sapphire Preferred", cathyMultiplier: "2x", note: ""),
        SwipeRow(category: "Flights (via Amex Travel)",
                 elisaCard: "Amex Platinum",      elisaMultiplier: "5x",
                 cathyCard: nil,                  cathyMultiplier: "—",  note: "Elisa only"),
        SwipeRow(category: "Flights (via Chase Travel)",
                 elisaCard: "Venture X",           elisaMultiplier: "5x",
                 cathyCard: "Chase Sapphire Preferred", cathyMultiplier: "5x", note: ""),
        SwipeRow(category: "Flights (via Capital One)",
                 elisaCard: "Venture X",           elisaMultiplier: "5x",
                 cathyCard: nil,                  cathyMultiplier: "—",  note: "Elisa only"),
        SwipeRow(category: "Hotels (direct)",
                 elisaCard: "Amex Platinum",      elisaMultiplier: "5x",
                 cathyCard: "Chase Sapphire Preferred", cathyMultiplier: "2x", note: ""),
        SwipeRow(category: "Hotels (via Chase Travel)",
                 elisaCard: "Venture X",           elisaMultiplier: "10x",
                 cathyCard: "Chase Sapphire Preferred", cathyMultiplier: "5x", note: ""),
        SwipeRow(category: "Hotels (via Capital One)",
                 elisaCard: "Venture X",           elisaMultiplier: "10x",
                 cathyCard: nil,                  cathyMultiplier: "—",  note: "Elisa only"),
        SwipeRow(category: "Rental Cars (via Capital One)",
                 elisaCard: "Venture X",           elisaMultiplier: "10x",
                 cathyCard: nil,                  cathyMultiplier: "—",  note: "Elisa only"),
        SwipeRow(category: "Dining",
                 elisaCard: "Chase Sapphire Preferred", elisaMultiplier: "3x",
                 cathyCard: "Bilt Palladium",     cathyMultiplier: "3x",
                 note: "Cathy: Bilt until threshold → CSP"),
        SwipeRow(category: "Online Grocery",
                 elisaCard: "Chase Sapphire Preferred", elisaMultiplier: "3x",
                 cathyCard: "Chase Sapphire Preferred", cathyMultiplier: "3x", note: ""),
        SwipeRow(category: "Streaming",
                 elisaCard: "Chase Sapphire Preferred", elisaMultiplier: "3x",
                 cathyCard: "Chase Sapphire Preferred", cathyMultiplier: "3x", note: ""),
        SwipeRow(category: "Direct Travel (other)",
                 elisaCard: "Chase Sapphire Preferred", elisaMultiplier: "2x",
                 cathyCard: "Chase Sapphire Preferred", cathyMultiplier: "2x", note: ""),
        SwipeRow(category: "Everyday Spend",
                 elisaCard: "Venture X",           elisaMultiplier: "2x",
                 cathyCard: "Bilt Palladium",     cathyMultiplier: "2x",
                 note: "Cathy: Bilt until threshold → CSP"),
        SwipeRow(category: "Rent / Mortgage",
                 elisaCard: "Venture X",           elisaMultiplier: "2x",
                 cathyCard: "Bilt Palladium",     cathyMultiplier: "1x",
                 note: "Bilt: no fee on rent payments"),
    ]

    var body: some View {
        ZStack {
            Color.sunBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                // Person filter pills
                HStack(spacing: 8) {
                    filterPill("All",   active: personFilter == .all)   { personFilter = .all }
                    filterPill("Elisa", active: personFilter == .elisa) { personFilter = .elisa }
                    filterPill("Cathy", active: personFilter == .cathy) { personFilter = .cathy }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                List {
                    ForEach(rows, id: \.category) { row in
                        rowView(row)
                            .listRowBackground(Color.sunSurface)
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("Swipe Guide")
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(Color.sunSurface, for: .navigationBar)
    }

    @ViewBuilder
    private func rowView(_ row: SwipeRow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(row.category)
                .font(.system(size: 14, weight: .medium, design: .serif))
                .foregroundStyle(Color.sunText)

            HStack(spacing: 16) {
                if personFilter == .all || personFilter == .elisa {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Elisa")
                            .font(.system(size: 10, design: .serif))
                            .foregroundStyle(Color.sunSecondary)
                        cardChip(name: shortName(row.elisaCard),
                                 color: cardColor(row.elisaCard),
                                 multiplier: row.elisaMultiplier)
                    }
                }
                if personFilter == .all || personFilter == .cathy {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Cathy")
                            .font(.system(size: 10, design: .serif))
                            .foregroundStyle(Color.sunSecondary)
                        cardChip(name: shortName(row.cathyCard),
                                 color: cardColor(row.cathyCard),
                                 multiplier: row.cathyMultiplier)
                    }
                }
                Spacer()
            }

            if !row.note.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 10, design: .serif))
                    Text(row.note)
                        .font(.system(size: 11, design: .serif))
                }
                .foregroundStyle(Color.sunAccent.opacity(0.8))
            }
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func cardChip(name: String?, color: String, multiplier: String) -> some View {
        if let name {
            HStack(spacing: 4) {
                Text(name)
                    .font(.system(size: 11, weight: .medium, design: .serif))
                    .foregroundStyle(Color(hex: color))
                Text(multiplier)
                    .font(.system(size: 11, weight: .bold, design: .serif))
                    .foregroundStyle(Color.sunAccent)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(hex: color).opacity(0.15))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color(hex: color).opacity(0.35), lineWidth: 1))
        } else {
            Text("—")
                .font(.system(size: 12, design: .serif))
                .foregroundStyle(Color.sunSecondary)
        }
    }

    private func shortName(_ card: String?) -> String? {
        guard let card else { return nil }
        switch card {
        case "Amex Platinum":           return "Platinum"
        case "Chase Sapphire Preferred": return "CSP"
        case "Venture X":               return "Venture X"
        case "Bilt Palladium":          return "Bilt"
        default:                         return card
        }
    }

    private func cardColor(_ card: String?) -> String {
        guard let card else { return "#6B7280" }
        switch card {
        case "Amex Platinum":           return "#60A5FA"
        case "Chase Sapphire Preferred": return "#1E3A8A"
        case "Venture X":               return "#A78BFA"
        case "Bilt Palladium":          return "#34D399"
        default:                         return "#6B7280"
        }
    }

    private func filterPill(_ label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: .medium, design: .serif))
                .foregroundStyle(active ? Color.sunBackground : Color.sunText)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(active ? Color.sunAccent : Color.sunSurface)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(active ? Color.sunAccent : Color.white.opacity(0.15), lineWidth: 1))
                .shadow(color: active ? Color.sunAccent.opacity(0.4) : .clear, radius: 6)
        }
        .buttonStyle(.plain)
    }
}
