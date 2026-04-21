import SwiftUI

struct CardsView: View {
    var body: some View {
        NavigationStack {
            ZStack {
                Color.sunBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        NavigationLink(destination: SwipeGuideView()) {
                            hubCell(title: "Swipe Guide",
                                    subtitle: "Which card earns most",
                                    icon: "creditcard.fill",
                                    color: "#FBBF24")
                        }
                        .buttonStyle(.plain)

                        NavigationLink(destination: CreditsListView()) {
                            hubCell(title: "Credits Tracker",
                                    subtitle: "Track your credits",
                                    icon: "checkmark.seal.fill",
                                    color: "#34D399")
                        }
                        .buttonStyle(.plain)

                        NavigationLink(destination: BenefitsView()) {
                            hubCell(title: "Benefits & Status",
                                    subtitle: "Lounges, hotel & rental status",
                                    icon: "star.circle.fill",
                                    color: "#A78BFA")
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)
                }
            }
            .navigationTitle("Cards")
            .navigationBarTitleDisplayMode(.large)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(Color.sunSurface, for: .navigationBar)
        }
    }

    private func hubCell(title: String, subtitle: String, icon: String, color: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 28, design: .serif))
                .foregroundStyle(Color(hex: color))
                .frame(width: 56, height: 56)
                .background(Color(hex: color).opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 14))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold, design: .serif))
                    .fontDesign(.serif)
                    .foregroundStyle(Color.sunText)
                Text(subtitle)
                    .font(.system(size: 13, design: .serif))
                    .foregroundStyle(Color.sunSecondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold, design: .serif))
                .foregroundStyle(Color.sunSecondary)
        }
        .padding(16)
        .background(Color.sunSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
