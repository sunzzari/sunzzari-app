import SwiftUI
import CoreLocation

/// "Find it": gives a place with no pin its address and pin. Opened from an
/// Around Town place that is not on the map. The lookup and the save both run
/// on the travel map server, the same routes as the website's "Find it".
struct PlaceFinderSheet: View {
    let item: AroundTownItem
    /// Reloads Around Town so the new pin shows.
    let onSaved: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var address: String
    @State private var pin: CLLocationCoordinate2D?
    @State private var isSaving = false
    @State private var message: String?

    init(item: AroundTownItem, onSaved: @escaping () async -> Void) {
        self.item = item
        self.onSaved = onSaved
        _address = State(initialValue: item.address)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.sunBackground.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(item.subtitle.isEmpty ? "No area on this place yet." : item.subtitle)
                            .font(.system(.subheadline, design: .serif))
                            .foregroundStyle(Color.sunSecondary)

                        Text("Tap the magnifier to search for it, then tap the right match. Or type its street address.")
                            .font(.system(.caption, design: .serif))
                            .foregroundStyle(Color.sunSecondary)

                        AddressLookupField(address: $address, pin: $pin) {
                            AddressLookupField.Context(
                                name: item.name,
                                isRestaurant: item.kind == .restaurant,
                                neighborhood: item.neighborhood,
                                location: item.locationText
                            )
                        }

                        if let message {
                            Text(message)
                                .font(.system(.caption, design: .serif))
                                .foregroundStyle(.red)
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle(item.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Color.sunSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if isSaving {
                        ProgressView().tint(Color.sunAccent)
                    } else {
                        Button("Save") { Task { await save() } }
                            .foregroundStyle(Color.sunAccent)
                            .disabled(address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
    }

    private func save() async {
        isSaving = true
        message = nil
        defer { isSaving = false }
        do {
            let placed = try await AroundTownService.shared.saveLocation(
                pageID: item.id,
                address: address.trimmingCharacters(in: .whitespacesAndNewlines),
                pin: pin
            )
            guard placed else {
                message = "Saved the address, but it could not be pinned. Tap the magnifier and pick a match."
                return
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            await onSaved()
            dismiss()
        } catch {
            message = error.localizedDescription
        }
    }
}
