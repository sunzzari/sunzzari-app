import SwiftUI

struct AddRestaurantView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var beenThere = false
    @State private var preference: Restaurant.Preference? = nil
    @State private var location = ""
    @State private var neighborhood = ""
    @State private var selectedGoodFor: Set<String> = []
    @State private var topDishes = ""
    @State private var comments = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    // AI autofill
    @State private var aiQuery = ""
    @State private var isAILoading = false
    @State private var aiMessage: String? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                Color.sunBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {

                        aiAutofillSection

                        formField(label: "Name", icon: "fork.knife") {
                            TextField("Restaurant name", text: $name)
                                .padding()
                                .background(Color.sunSurface)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .foregroundStyle(Color.sunText)
                        }

                        formField(label: "Been There?", icon: "checkmark.circle") {
                            Toggle("", isOn: $beenThere.animation())
                                .tint(.sunAccent)
                                .padding()
                                .background(Color.sunSurface)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }

                        if beenThere {
                            formField(label: "Preference", icon: "star") {
                                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                                    ForEach(Restaurant.Preference.allCases, id: \.self) { pref in
                                        Button {
                                            preference = preference == pref ? nil : pref
                                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                        } label: {
                                            Text(pref.rawValue)
                                                .font(.system(size: 14, weight: .semibold, design: .serif))
                                                .frame(maxWidth: .infinity)
                                                .padding(.vertical, 12)
                                                .background(
                                                    preference == pref
                                                        ? Color(hex: pref.colorHex).opacity(0.25)
                                                        : Color.sunSurface
                                                )
                                                .foregroundStyle(
                                                    preference == pref
                                                        ? Color(hex: pref.colorHex)
                                                        : Color.sunSecondary
                                                )
                                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 12)
                                                        .strokeBorder(
                                                            preference == pref
                                                                ? Color(hex: pref.colorHex)
                                                                : Color.clear,
                                                            lineWidth: 1.5
                                                        )
                                                )
                                        }
                                    }
                                }
                            }
                        }

                        formField(label: "Location", icon: "mappin") {
                            Picker("Location", selection: $location) {
                                Text("None").tag("")
                                ForEach(Restaurant.locationOptions, id: \.self) { loc in
                                    Text(loc).tag(loc)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(Color.sunAccent)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(Color.sunSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }

                        formField(label: "Neighborhood", icon: "building.2") {
                            TextField("e.g. Silver Lake, West Village", text: $neighborhood)
                                .padding()
                                .background(Color.sunSurface)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .foregroundStyle(Color.sunText)
                        }

                        formField(label: "Good For", icon: "tag") {
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                                ForEach(Restaurant.goodForOptions, id: \.self) { tag in
                                    Button {
                                        if selectedGoodFor.contains(tag) { selectedGoodFor.remove(tag) }
                                        else { selectedGoodFor.insert(tag) }
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    } label: {
                                        Text(tag)
                                            .font(.system(size: 11, weight: .semibold, design: .serif))
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.7)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 8)
                                            .background(
                                                selectedGoodFor.contains(tag)
                                                    ? Color.sunAccent.opacity(0.2)
                                                    : Color.sunSurface
                                            )
                                            .foregroundStyle(
                                                selectedGoodFor.contains(tag)
                                                    ? Color.sunAccent
                                                    : Color.sunSecondary
                                            )
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                    }
                                }
                            }
                        }

                        formField(label: "Top Dishes (optional)", icon: "menucard") {
                            TextField("Dishes worth ordering...", text: $topDishes, axis: .vertical)
                                .lineLimit(3...5)
                                .padding()
                                .background(Color.sunSurface)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .foregroundStyle(Color.sunText)
                        }

                        formField(label: "Comments (optional)", icon: "note.text") {
                            TextField("Notes, vibes, context...", text: $comments, axis: .vertical)
                                .lineLimit(3...5)
                                .padding()
                                .background(Color.sunSurface)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .foregroundStyle(Color.sunText)
                        }

                        if let errorMessage {
                            Text(errorMessage).font(.system(.caption, design: .serif)).foregroundStyle(.red)
                        }

                        Button { Task { await save() } } label: {
                            HStack(spacing: 10) {
                                if isSaving { ProgressView().tint(.sunBackground) }
                                Text(isSaving ? "Saving..." : "Save Restaurant")
                                    .font(.system(.headline, design: .serif))
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(name.isEmpty ? Color.sunSurface : Color.sunAccent)
                            .foregroundStyle(name.isEmpty ? Color.sunSecondary : Color.sunBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .disabled(name.isEmpty || isSaving)
                    }
                    .padding(20)
                }
            }
            .navigationTitle("New Restaurant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Color.sunSecondary)
                }
            }
        }
    }

    // MARK: - AI Autofill Section

    private var aiAutofillSection: some View {
        VStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
                Label("Autofill with AI", systemImage: "sparkles")
                    .font(.system(.caption, design: .serif, weight: .semibold))
                    .foregroundStyle(Color.sunSecondary)

                HStack(spacing: 10) {
                    TextField("e.g. Bestia, Los Angeles", text: $aiQuery)
                        .padding()
                        .background(Color.sunSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(Color.sunText)
                        .onSubmit { Task { await autofill() } }

                    Button {
                        Task { await autofill() }
                    } label: {
                        Group {
                            if isAILoading {
                                ProgressView().tint(Color.sunAccent)
                            } else {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 18, weight: .semibold, design: .serif))
                                    .foregroundStyle(aiQuery.isEmpty ? Color.sunSecondary : Color.sunAccent)
                            }
                        }
                        .frame(width: 50, height: 50)
                        .background(Color.sunSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(aiQuery.isEmpty || isAILoading)
                }
            }

            if let msg = aiMessage {
                Text(msg)
                    .font(.system(.caption, design: .serif))
                    .foregroundStyle(msg.hasPrefix("✓") ? Color.green : Color.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Color.white.opacity(0.15).frame(height: 0.5)
                Text("or fill manually")
                    .font(.system(.caption, design: .serif))
                    .foregroundStyle(Color.sunSecondary)
                    .fixedSize()
                    .padding(.horizontal, 8)
                Color.white.opacity(0.15).frame(height: 0.5)
            }
        }
    }

    // MARK: - AI Logic

    private func autofill() async {
        guard !aiQuery.isEmpty else { return }
        isAILoading = true
        aiMessage = nil
        defer { isAILoading = false }
        do {
            let info = try await AnthropicService.shared.extractRestaurantInfo(query: aiQuery)
            if !info.name.isEmpty { name = info.name }
            if !info.location.isEmpty, Restaurant.locationOptions.contains(info.location) {
                location = info.location
            }
            if !info.neighborhood.isEmpty { neighborhood = info.neighborhood }
            let validTags = info.goodFor.filter { Restaurant.goodForOptions.contains($0) }
            if !validTags.isEmpty { selectedGoodFor = Set(validTags) }
            if !info.topDishes.isEmpty { topDishes = info.topDishes }
            if !info.comments.isEmpty { comments = info.comments }
            aiMessage = "✓ Filled in — review and adjust before saving"
        } catch {
            aiMessage = "Could not autofill: \(error.localizedDescription)"
        }
    }

    // MARK: - Helpers

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
        do {
            let r = Restaurant(
                id:           UUID().uuidString,
                name:         name,
                beenThere:    beenThere,
                preference:   beenThere ? preference : nil,
                location:     location,
                neighborhood: neighborhood,
                goodFor:      Array(selectedGoodFor),
                topDishes:    topDishes,
                comments:     comments
            )
            try await NotionService.shared.createRestaurant(r)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            NotionService.shared.invalidateRestaurants()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
