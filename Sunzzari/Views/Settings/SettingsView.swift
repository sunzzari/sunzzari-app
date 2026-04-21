import SwiftUI

struct SettingsView: View {
    let onComplete: () -> Void

    @State private var selected: SunzzariPerson? = AppIdentity.current

    var body: some View {
        ZStack {
            Color.sunBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                VStack(spacing: 6) {
                    Text("My Identity")
                        .font(.system(size: 26, weight: .bold, design: .serif))
                        .fontDesign(.serif)
                        .foregroundStyle(Color.sunText)
                    Text("Who are you?")
                        .font(.system(size: 14, design: .serif))
                        .foregroundStyle(Color.sunSecondary)
                }
                .padding(.top, 40)
                .padding(.bottom, 32)

                // Identity cards
                VStack(spacing: 16) {
                    identityCard(
                        person: .branch,
                        emoji: "🌿",
                        name: "Branch",
                        subtitle: "Elisa"
                    )
                    identityCard(
                        person: .hummingbird,
                        emoji: "🕊️",
                        name: "Hummingbird",
                        subtitle: "Cathy"
                    )
                }
                .padding(.horizontal, 24)

                Spacer()

                // Footer note
                Text("You can change this anytime in the Settings tab.")
                    .font(.system(size: 12, design: .serif))
                    .foregroundStyle(Color.sunSecondary.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 40)
            }
        }
    }

    private func identityCard(person: SunzzariPerson, emoji: String, name: String, subtitle: String) -> some View {
        let isSelected = selected == person

        return Button {
            selected = person
            AppIdentity.current = person
            // Re-attempt device token storage now that identity is confirmed
            Task { await StatusService.shared.retryTokenStorage() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                onComplete()
            }
        } label: {
            HStack(spacing: 16) {
                Text(emoji)
                    .font(.system(size: 40, design: .serif))
                    .frame(width: 56, height: 56)
                    .background(Color.white.opacity(0.07))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(name)
                        .font(.system(size: 18, weight: .bold, design: .serif))
                        .fontDesign(.serif)
                        .foregroundStyle(Color.sunText)
                    Text(subtitle)
                        .font(.system(size: 13, design: .serif))
                        .foregroundStyle(Color.sunSecondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22, design: .serif))
                        .foregroundStyle(Color.sunAccent)
                }
            }
            .padding(18)
            .background(Color.sunSurface)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? Color.sunAccent : Color.white.opacity(0.08), lineWidth: isSelected ? 2 : 1)
            )
            .shadow(color: isSelected ? Color.sunAccent.opacity(0.25) : .clear, radius: 8)
        }
        .buttonStyle(.plain)
    }
}
