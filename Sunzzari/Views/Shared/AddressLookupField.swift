import SwiftUI
import CoreLocation

/// Address entry with the free place lookup. Tapping the magnifier asks the
/// travel map server (OpenStreetMap and the US Census, no Google) for up to
/// five real matches inside the place's own area; tapping one sets the address
/// AND its pin. Typing clears the pin, and the server pins the typed address
/// itself when the form saves. Nothing is written from here.
///
/// The website's address field does the same thing against the same route, so
/// a place found on one is found the same way on the other.
struct AddressLookupField: View {
    /// What the server needs to fence the search to the right area.
    struct Context {
        let name: String
        let isRestaurant: Bool
        let neighborhood: String
        let location: String
    }

    @Binding var address: String
    @Binding var pin: CLLocationCoordinate2D?
    /// Built at tap time so it reflects the name / neighborhood typed so far.
    let context: () -> Context

    @State private var matches: [AroundTownService.Match] = []
    @State private var isSearching = false
    @State private var message: String?
    /// The address a tapped match set. Any other text means she typed, so the
    /// tapped pin no longer applies.
    @State private var pickedAddress: String?

    /// A typed street address ("123 Main St") is looked up as an address;
    /// otherwise the place's name is searched.
    private var query: String {
        let typed = address.trimmingCharacters(in: .whitespaces)
        if let first = typed.first, first.isNumber, typed.contains(" ") { return typed }
        return context().name.trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                TextField("Street address", text: $address, axis: .vertical)
                    .lineLimit(1...3)
                    .padding()
                    .background(Color.sunSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(Color.sunText)
                    .onChange(of: address) { _, new in
                        if new != pickedAddress { pin = nil }
                    }

                Button { Task { await search() } } label: {
                    Group {
                        if isSearching {
                            ProgressView().tint(Color.sunAccent)
                        } else {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(query.isEmpty ? Color.sunSecondary : Color.sunAccent)
                        }
                    }
                    .frame(width: 50, height: 50)
                    .background(Color.sunSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(query.isEmpty || isSearching)
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
                            pickedAddress = m.address
                            address = m.address
                            pin = CLLocationCoordinate2D(latitude: m.lat, longitude: m.lng)
                            matches = []
                            message = "Address and pin set. Save to keep them."
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                if !m.name.isEmpty {
                                    Text(m.name)
                                        .font(.system(.subheadline, design: .serif, weight: .semibold))
                                        .foregroundStyle(Color.sunText)
                                }
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
                    Button("None of these") {
                        matches = []
                        message = "Type the street address and tap the magnifier, or leave it blank."
                    }
                    .font(.system(.caption, design: .serif))
                    .foregroundStyle(Color.sunSecondary)
                }
            }
        }
    }

    private func search() async {
        let q = query
        guard !q.isEmpty else { return }
        let c = context()
        isSearching = true
        message = nil
        defer { isSearching = false }
        do {
            let answer = try await AroundTownService.shared.lookup(
                query: q, isRestaurant: c.isRestaurant, neighborhood: c.neighborhood, location: c.location
            )
            matches = answer.matches
            message = answer.matches.isEmpty
                ? (answer.note ?? "No matches. Type the street address and tap the magnifier, or leave it blank.")
                : "Tap the right one:"
        } catch {
            matches = []
            message = error.localizedDescription
        }
    }
}
