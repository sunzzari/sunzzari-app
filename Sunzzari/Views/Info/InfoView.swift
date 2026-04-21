import SwiftUI

struct InfoView: View {
    @State private var entries: [SunzzariInfoEntry] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.sunBackground.ignoresSafeArea()

                if isLoading {
                    ProgressView()
                        .tint(.sunAccent)
                } else if let error = errorMessage {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 36, design: .serif))
                            .foregroundStyle(Color.sunAccent)
                        Text(error)
                            .foregroundStyle(Color.sunSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                        Button("Retry") { Task { await load() } }
                            .foregroundStyle(Color.sunAccent)
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(entries) { entry in
                                NavigationLink(destination: InfoDetailView(entry: entry)) {
                                    infoCard(entry)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 20)
                    }
                }
            }
            .navigationTitle("Quick Reference")
            .navigationBarTitleDisplayMode(.large)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(Color.sunSurface, for: .navigationBar)
        }
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            entries = try await NotionService.shared.fetchSunzzariInfo()
        } catch {
            errorMessage = "Couldn't load reference data."
        }
        isLoading = false
    }

    @ViewBuilder
    private func infoCard(_ entry: SunzzariInfoEntry) -> some View {
        HStack(spacing: 16) {
            Image(systemName: entry.category.icon)
                .font(.system(size: 26, design: .serif))
                .foregroundStyle(Color(hex: entry.category.color))
                .frame(width: 52, height: 52)
                .background(Color(hex: entry.category.color).opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 13))

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.title)
                    .font(.system(size: 17, weight: .semibold, design: .serif))
                    .fontDesign(.serif)
                    .foregroundStyle(Color.sunText)
                Text(entry.category.rawValue)
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
