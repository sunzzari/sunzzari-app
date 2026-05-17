import SwiftUI
import MapKit
import CoreLocation

struct TripAssistantSheet: View {
    let items: [TripItem]
    let trip: Trip
    let userLocation: CLLocation?
    let onSelectItem: (TripItem) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var isLoading = false
    @State private var response: TripAssistantResponse?
    @State private var errorMessage: String?
    @State private var selectedItemID: String?
    @FocusState private var queryFocused: Bool

    private var matchedItems: [TripItem] {
        guard let response else { return [] }
        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        return response.matchedItemIds.compactMap { byID[$0] }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    inputRow

                    if let error = errorMessage {
                        errorBanner(error)
                    }

                    if let response {
                        responseSection(response)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.sunBackground)
            .navigationTitle("Trip Assistant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(Color.sunSurface, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.sunAccent)
                        .font(.system(.body, design: .serif))
                }
            }
        }
    }

    // MARK: - Input

    private var inputRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(.caption, design: .serif))
                .foregroundStyle(Color.sunAccent)

            TextField("Ask anything about your trip...", text: $query)
                .font(.system(.subheadline, design: .serif))
                .foregroundStyle(Color.sunText)
                .submitLabel(.send)
                .focused($queryFocused)
                .onSubmit { submit() }
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done") { queryFocused = false }
                            .font(.system(.body, design: .serif))
                    }
                }

            if isLoading {
                ProgressView()
                    .tint(Color.sunAccent)
                    .scaleEffect(0.8)
            } else {
                Button(action: submit) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(.title3, design: .serif))
                        .foregroundStyle(query.trimmingCharacters(in: .whitespaces).isEmpty ? Color.sunSecondary : Color.sunAccent)
                }
                .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.sunSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle")
            Text(message)
                .font(.system(.caption, design: .serif))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.red.opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Response

    @ViewBuilder
    private func responseSection(_ resp: TripAssistantResponse) -> some View {
        Text(resp.answer)
            .font(.system(.subheadline, design: .serif))
            .foregroundStyle(Color.sunText)
            .frame(maxWidth: .infinity, alignment: .leading)

        if !matchedItems.isEmpty {
            sectionHeader("From your trip", source: .notion)
            ForEach(matchedItems) { item in
                tripItemCard(item)
            }
        }

        if !resp.suggestions.isEmpty {
            sectionHeader("Suggestions", source: .claude)
            ForEach(resp.suggestions, id: \.name) { suggestion in
                suggestionCard(suggestion)
            }
        }
    }

    private enum ResultSource { case notion, claude }

    private func sectionHeader(_ title: String, source: ResultSource) -> some View {
        HStack(spacing: 6) {
            Text(title.uppercased())
                .font(.system(.caption2, design: .serif, weight: .semibold))
                .foregroundStyle(Color.sunSecondary)
                .tracking(0.8)

            sourceBadge(source)
        }
    }

    @ViewBuilder
    private func sourceBadge(_ source: ResultSource) -> some View {
        switch source {
        case .notion:
            Text("Notion")
                .font(.system(size: 9, weight: .semibold, design: .serif))
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color(hex: "#3B82F6"))
                .clipShape(Capsule())
        case .claude:
            HStack(spacing: 2) {
                Image(systemName: "sparkles")
                    .font(.system(size: 8, weight: .semibold))
                Text("Claude")
                    .font(.system(size: 9, weight: .semibold, design: .serif))
            }
            .foregroundStyle(Color.sunAccent)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Color.sunAccent.opacity(0.15))
            .clipShape(Capsule())
        }
    }

    private func tripItemCard(_ item: TripItem) -> some View {
        let isSelected = selectedItemID == item.id
        let hasLocation = item.hasCoordinates

        return Button {
            guard selectedItemID != item.id else { return }
            selectedItemID = item.id
            if hasLocation { onSelectItem(item) }
        } label: {
            HStack(spacing: 12) {
                if let type = item.type {
                    Image(systemName: type.sfSymbol)
                        .font(.system(.caption, design: .serif))
                        .foregroundStyle(Color(hex: type.colorHex))
                        .frame(width: 24)
                } else {
                    Image(systemName: "mappin")
                        .font(.system(.caption, design: .serif))
                        .foregroundStyle(Color.sunSecondary)
                        .frame(width: 24)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.system(.subheadline, design: .serif, weight: .medium))
                        .foregroundStyle(Color.sunText)
                    HStack(spacing: 6) {
                        if !item.legCity.isEmpty {
                            Text(item.legCity)
                                .font(.system(.caption2, design: .serif))
                                .foregroundStyle(Color.sunSecondary)
                        }
                        if let date = item.displayDate {
                            Text(date)
                                .font(.system(.caption2, design: .serif))
                                .foregroundStyle(Color.sunSecondary)
                        }
                    }
                    if !item.notes.isEmpty {
                        Text(item.notes)
                            .font(.system(.caption2, design: .serif))
                            .foregroundStyle(Color.sunSecondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                if isSelected {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(.subheadline, design: .serif))
                        .foregroundStyle(Color.sunAccent)
                } else if !hasLocation {
                    Image(systemName: "mappin.slash")
                        .font(.system(size: 11, design: .serif))
                        .foregroundStyle(Color.sunSecondary.opacity(0.5))
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold, design: .serif))
                        .foregroundStyle(Color.sunSecondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(Color.sunSurface)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.sunAccent : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }

    private func suggestionCard(_ suggestion: TripAssistantResponse.ExternalSuggestion) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: iconForType(suggestion.type))
                    .font(.system(.caption, design: .serif))
                    .foregroundStyle(Color.sunAccent)
                VStack(alignment: .leading, spacing: 1) {
                    Text(suggestion.name)
                        .font(.system(.subheadline, design: .serif, weight: .medium))
                        .foregroundStyle(Color.sunText)
                    Text("\(suggestion.type) · \(suggestion.neighborhood)")
                        .font(.system(.caption2, design: .serif))
                        .foregroundStyle(Color.sunSecondary)
                }
                Spacer()
            }
            Text(suggestion.reason)
                .font(.system(.caption, design: .serif))
                .foregroundStyle(Color.sunText.opacity(0.8))

            Button {
                openInMaps(name: suggestion.name, neighborhood: suggestion.neighborhood)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "map.fill")
                        .font(.system(.caption2, design: .serif))
                    Text("Open in Maps")
                        .font(.system(.caption, design: .serif, weight: .medium))
                }
                .foregroundStyle(Color.sunAccent)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.sunAccent.opacity(0.12))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.sunSurface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Actions

    private func submit() {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !isLoading else { return }
        errorMessage = nil
        selectedItemID = nil
        isLoading = true

        Task {
            do {
                let coord = userLocation.map {
                    CLLocationCoordinate2D(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)
                }
                let result = try await AnthropicService.shared.askTripAssistant(
                    query: trimmed,
                    items: items,
                    trip: trip,
                    userLocation: coord
                )
                await MainActor.run {
                    response = result
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }

    private func openInMaps(name: String, neighborhood: String) {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "\(name) \(neighborhood)"
        let search = MKLocalSearch(request: request)
        search.start { response, _ in
            if let item = response?.mapItems.first {
                item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
            } else {
                let query = "\(name) \(neighborhood)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                if let url = URL(string: "https://maps.apple.com/?q=\(query)") {
                    UIApplication.shared.open(url)
                }
            }
        }
    }

    private func iconForType(_ type: String) -> String {
        switch type.lowercased() {
        case "restaurant", "wine bar", "bar", "cafe", "bakery": return "fork.knife"
        case "hotel":    return "bed.double.fill"
        case "activity": return "figure.hiking"
        case "winery", "cellar", "cave": return "wineglass"
        default:         return "mappin"
        }
    }
}
