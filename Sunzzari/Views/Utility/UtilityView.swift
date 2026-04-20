import SwiftUI

struct UtilityView: View {
    private struct Row: Identifiable {
        let id = UUID()
        let label: String
        let symbol: String
        let colorHex: String
        let destination: AnyView
    }

    private var rows: [Row] {
        [
            Row(label: "Best Of", symbol: "star.circle.fill", colorHex: "#FBBF24",
                destination: AnyView(BestOfView())),
            Row(label: "Search", symbol: "magnifyingglass", colorHex: "#38BDF8",
                destination: AnyView(SearchView())),
            Row(label: "Cycle", symbol: "calendar.circle.fill", colorHex: "#F472B6",
                destination: AnyView(CycleView())),
            Row(label: "Cards", symbol: "creditcard.circle.fill", colorHex: "#A78BFA",
                destination: AnyView(CardsView())),
            Row(label: "Reference", symbol: "bookmark.circle.fill", colorHex: "#34D399",
                destination: AnyView(InfoView())),
            Row(label: "Settings", symbol: "gearshape.fill", colorHex: "#9CA3AF",
                destination: AnyView(SettingsView(onComplete: {}))),
            Row(label: "Nits & Bugs", symbol: "ladybug", colorHex: "#EF4444",
                destination: AnyView(NitsAndBugsView())),
        ]
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.sunBackground.ignoresSafeArea()

                List {
                    ForEach(rows) { row in
                        NavigationLink(destination: row.destination) {
                            rowLabel(row)
                        }
                        .listRowBackground(Color.sunSurface)
                        .listRowSeparatorTint(Color.white.opacity(0.06))
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("More")
            .navigationBarTitleDisplayMode(.large)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }

    @ViewBuilder
    private func rowLabel(_ row: Row) -> some View {
        HStack(spacing: 14) {
            Image(systemName: row.symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color(hex: row.colorHex))
                .frame(width: 28, height: 28)

            Text(row.label)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.sunText)

            Spacer()
        }
        .padding(.vertical, 4)
    }
}
