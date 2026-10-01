import SwiftUI
import CoreLocation

/// Edit an existing restaurant: been there, preference, review, dishes, address.
/// The address and its pin are saved through the travel map server; everything
/// else goes to Notion in one request.
struct RestaurantEditView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Restaurant
    /// The pin of a tapped lookup match; nil when the address was typed or untouched.
    @State private var pin: CLLocationCoordinate2D?
    private let originalAddress: String
    @State private var isSaving = false
    @State private var errorMessage: String?
    let onSaved: (Restaurant) -> Void

    init(restaurant: Restaurant, onSaved: @escaping (Restaurant) -> Void) {
        _draft = State(initialValue: restaurant)
        originalAddress = restaurant.address
        self.onSaved = onSaved
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.sunBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        formField(label: "Name", icon: "fork.knife") {
                            TextField("Restaurant name", text: $draft.name)
                                .padding()
                                .background(Color.sunSurface)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .foregroundStyle(Color.sunText)
                        }

                        formField(label: "Been There?", icon: "checkmark.circle") {
                            Toggle("", isOn: $draft.beenThere.animation())
                                .tint(.sunAccent)
                                .padding()
                                .background(Color.sunSurface)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .onChange(of: draft.beenThere) { _, isOn in
                                    if isOn { draft.thinkingAbout = false }
                                }
                        }

                        if !draft.beenThere {
                            formField(label: "Want to Try?", icon: "bookmark") {
                                Toggle("", isOn: $draft.thinkingAbout.animation())
                                    .tint(.sunAccent)
                                    .padding()
                                    .background(Color.sunSurface)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }

                        formField(label: "Preference", icon: "star") {
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                                ForEach(Restaurant.Preference.allCases, id: \.self) { pref in
                                    let on = draft.preference == pref
                                    Button {
                                        draft.preference = on ? nil : pref
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    } label: {
                                        Text(pref.rawValue)
                                            .font(.system(size: 14, weight: .semibold, design: .serif))
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 12)
                                            .background(on ? Color(hex: pref.colorHex).opacity(0.25) : Color.sunSurface)
                                            .foregroundStyle(on ? Color(hex: pref.colorHex) : Color.sunSecondary)
                                            .clipShape(RoundedRectangle(cornerRadius: 12))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .strokeBorder(on ? Color(hex: pref.colorHex) : Color.clear, lineWidth: 1.5)
                                            )
                                    }
                                }
                            }
                        }

                        formField(label: "Review / Comments", icon: "note.text") {
                            TextField("What did you think?", text: $draft.comments, axis: .vertical)
                                .lineLimit(3...8)
                                .padding()
                                .background(Color.sunSurface)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .foregroundStyle(Color.sunText)
                        }

                        formField(label: "Top Dishes", icon: "menucard") {
                            TextField("Dishes worth ordering...", text: $draft.topDishes, axis: .vertical)
                                .lineLimit(2...5)
                                .padding()
                                .background(Color.sunSurface)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .foregroundStyle(Color.sunText)
                        }

                        formField(label: "Address", icon: "mappin.and.ellipse") {
                            AddressLookupField(address: $draft.address, pin: $pin) {
                                AddressLookupField.Context(
                                    name: draft.name,
                                    isRestaurant: true,
                                    neighborhood: draft.neighborhood,
                                    location: draft.location
                                )
                            }
                        }

                        formField(label: "Neighborhood", icon: "building.2") {
                            TextField("e.g. Silver Lake, West Village", text: $draft.neighborhood)
                                .padding()
                                .background(Color.sunSurface)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .foregroundStyle(Color.sunText)
                        }

                        formField(label: "Location", icon: "mappin") {
                            Picker("Location", selection: $draft.location) {
                                Text("None").tag("")
                                ForEach(locationOptions, id: \.self) { Text($0).tag($0) }
                            }
                            .pickerStyle(.menu)
                            .tint(Color.sunAccent)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(Color.sunSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }

                        formField(label: "Good For", icon: "tag") {
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                                ForEach(Restaurant.goodForOptions, id: \.self) { tag in
                                    let on = draft.goodFor.contains(tag)
                                    Button {
                                        if on { draft.goodFor.removeAll { $0 == tag } } else { draft.goodFor.append(tag) }
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    } label: {
                                        Text(tag)
                                            .font(.system(size: 11, weight: .semibold, design: .serif))
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.7)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 8)
                                            .background(on ? Color.sunAccent.opacity(0.2) : Color.sunSurface)
                                            .foregroundStyle(on ? Color.sunAccent : Color.sunSecondary)
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                    }
                                }
                            }
                        }

                        if let errorMessage {
                            Text(errorMessage).font(.system(.caption, design: .serif)).foregroundStyle(.red)
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle(draft.name.isEmpty ? "Restaurant" : draft.name)
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
                            .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
    }

    /// The hardcoded list plus whatever this row already holds, so a Location
    /// added in Notion after the list was written still shows as selected.
    private var locationOptions: [String] {
        let base = Restaurant.locationOptions
        return draft.location.isEmpty || base.contains(draft.location) ? base : base + [draft.location]
    }

    private func formField<C: View>(label: String, icon: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(label, systemImage: icon)
                .font(.system(.caption, design: .serif, weight: .semibold))
                .foregroundStyle(Color.sunSecondary)
            content()
        }
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        var r = draft
        r.address = r.address.trimmingCharacters(in: .whitespacesAndNewlines)
        if r.beenThere { r.thinkingAbout = false }
        do {
            try await NotionService.shared.updateRestaurant(r)
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        // The address goes up only when it changed or a match was tapped, after
        // the row itself, so the server checks the pin against the area just saved.
        if pin != nil || r.address != originalAddress {
            do {
                try await AroundTownService.shared.saveLocation(pageID: r.id, address: r.address, pin: pin)
            } catch {
                onSaved(r)
                errorMessage = "Everything else saved, but the address did not: \(error.localizedDescription)"
                return
            }
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onSaved(r)
        dismiss()
    }
}
