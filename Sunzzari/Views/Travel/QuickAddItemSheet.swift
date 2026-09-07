import SwiftUI

/// Add something to the trip from the road.
///
/// Writes a real Trip Item to Notion, so it shows up on the web itinerary and
/// on the trip's Notion page too, not just on this phone.
///
/// Two placements only, and they follow the status rules the trip skills
/// already enforce rather than inventing new ones:
///   - "Add to this day"  -> Status `Assigned`, WITH `Assigned to Date`
///   - "Just save it"     -> Status `Shortlisted`, no date
/// `Confirmed` is deliberately not offered: a trip item is never upgraded to
/// Confirmed without explicit approval, and a form typed on a phone cannot
/// carry that decision.
struct QuickAddItemSheet: View {
    let trip: Trip
    /// The day being viewed, used for "add to this day" and for the leg.
    let dayString: String
    let legCity: String
    /// Handed the created item so the caller can refresh and show it.
    let onCreated: (TripItem) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var type: TripItem.ItemType = .restaurant
    @State private var addToDay = true
    @State private var timeText = ""
    @State private var notes = ""

    @State private var isSaving = false
    @State private var errorMessage: String?

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSaving
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .font(.system(.body, design: .serif))
                        .foregroundStyle(Color.sunText)
                        .submitLabel(.done)

                    Picker("Type", selection: $type) {
                        ForEach(TripItem.ItemType.allCases, id: \.self) { option in
                            Label(option.rawValue, systemImage: option.sfSymbol).tag(option)
                        }
                    }
                    .font(.system(.body, design: .serif))
                }
                .listRowBackground(Color.sunSurface)

                Section {
                    Picker("", selection: $addToDay) {
                        Text("Add to this day").tag(true)
                        Text("Just save it").tag(false)
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text(addToDay
                         ? "Goes on \(friendlyDay) as a planned item."
                         : "Saved to the trip with no date, so it shows up as a candidate.")
                        .font(.system(.caption, design: .serif))
                        .foregroundStyle(Color.sunSecondary)
                }
                .listRowBackground(Color.sunSurface)

                Section {
                    TextField("Time (optional)", text: $timeText)
                        .font(.system(.body, design: .serif))
                    TextField("Note (optional)", text: $notes, axis: .vertical)
                        .lineLimit(1...4)
                        .font(.system(.body, design: .serif))
                } footer: {
                    Text("Time takes anything: 9:30am, or morning, or evening. Leave it blank if you don't know.")
                        .font(.system(.caption, design: .serif))
                        .foregroundStyle(Color.sunSecondary)
                }
                .listRowBackground(Color.sunSurface)

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(.caption, design: .serif))
                            .foregroundStyle(Color(hex: "#F97316"))
                    }
                    .listRowBackground(Color.sunSurface)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.sunBackground)
            .navigationTitle("Add to \(trip.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(Color.sunSurface, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.sunSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView().tint(Color.sunAccent)
                    } else {
                        Button("Add") { Task { await save() } }
                            .foregroundStyle(canSave ? Color.sunAccent : Color.sunSecondary)
                            .disabled(!canSave)
                    }
                }
            }
        }
    }

    private var friendlyDay: String {
        let parser = DateFormatter()
        parser.dateFormat = "yyyy-MM-dd"
        parser.timeZone = TimeZone(identifier: "UTC")
        guard let date = parser.date(from: dayString) else { return dayString }
        let out = DateFormatter()
        out.dateFormat = "EEEE, MMMM d"
        out.timeZone = TimeZone(identifier: "UTC")
        return out.string(from: date)
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        do {
            let created = try await TravelService.shared.createTripItem(
                tripId: trip.id,
                name: name,
                type: type,
                placement: addToDay ? .onDay(dayString) : .saveForLater,
                legCity: legCity,
                timeText: timeText,
                notes: notes
            )
            onCreated(created)
            dismiss()
        } catch {
            // Keep everything she typed on screen. A failed write that also
            // eats the text is two problems instead of one.
            errorMessage = error.localizedDescription
            isSaving = false
        }
    }
}
