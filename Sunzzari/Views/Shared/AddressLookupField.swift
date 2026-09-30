import SwiftUI

/// Address entry with a Google Places lookup. Tapping "Find address" shows up to
/// five real matches; tapping one is the confirmation and fills the field.
/// Nothing is written to Notion from here -- the enclosing form saves.
struct AddressLookupField: View {
    @Binding var address: String
    /// Built at tap time so it reflects the name / neighborhood typed so far.
    let query: () -> String

    @State private var matches: [PlacesService.PlaceMatch] = []
    @State private var isSearching = false
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                TextField("Street address", text: $address, axis: .vertical)
                    .lineLimit(1...3)
                    .padding()
                    .background(Color.sunSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(Color.sunText)

                Button { Task { await search() } } label: {
                    Group {
                        if isSearching {
                            ProgressView().tint(Color.sunAccent)
                        } else {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(query().isEmpty ? Color.sunSecondary : Color.sunAccent)
                        }
                    }
                    .frame(width: 50, height: 50)
                    .background(Color.sunSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(query().isEmpty || isSearching)
                .accessibilityLabel("Find address")
            }

            if let message {
                Text(message)
                    .font(.system(.caption, design: .serif))
                    .foregroundStyle(Color.sunSecondary)
            }

            if !matches.isEmpty {
                VStack(spacing: 6) {
                    ForEach(matches) { m in
                        Button {
                            address = m.address
                            matches = []
                            message = "✓ Address set. Save to keep it."
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(m.name)
                                    .font(.system(.subheadline, design: .serif, weight: .semibold))
                                    .foregroundStyle(Color.sunText)
                                Text(m.address)
                                    .font(.system(.caption, design: .serif))
                                    .foregroundStyle(Color.sunSecondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(Color.sunSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                    Button("None of these") { matches = []; message = "Type the address, or leave it blank." }
                        .font(.system(.caption, design: .serif))
                        .foregroundStyle(Color.sunSecondary)
                }
            }
        }
    }

    private func search() async {
        let q = query()
        guard !q.isEmpty else { return }
        isSearching = true
        message = nil
        defer { isSearching = false }
        do {
            matches = try await PlacesService.shared.searchPlaces(query: q)
            if matches.isEmpty { message = "No matches. Type the address, or leave it blank." }
            else { message = "Tap the right one:" }
        } catch {
            matches = []
            message = error.localizedDescription
        }
    }
}
