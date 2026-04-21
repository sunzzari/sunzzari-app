import SwiftUI

struct LoadingView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(.sunAccent)
                .scaleEffect(1.3)
            Text("Loading...")
                .font(.system(.caption, design: .serif))
                .foregroundStyle(Color.sunSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.sunBackground)
    }
}

struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 56, design: .serif))
                .foregroundStyle(Color.sunAccent.opacity(0.6))
            Text(title)
                .font(.system(.headline, design: .serif))
                .foregroundStyle(Color.sunText)
            Text(subtitle)
                .font(.system(.subheadline, design: .serif))
                .foregroundStyle(Color.sunSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.sunBackground)
    }
}
