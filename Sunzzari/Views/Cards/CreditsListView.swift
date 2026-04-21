import SwiftUI

struct CreditsListView: View {
    @State private var credits: [CreditEntry] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var personFilter: PersonFilter = .all

    enum PersonFilter: String, CaseIterable {
        case all   = "All"
        case elisa = "Elisa"
        case cathy = "Cathy"
    }

    // All credits visible for the current person filter
    private var filteredCredits: [CreditEntry] {
        credits.filter { c in
            switch personFilter {
            case .all:   return true
            case .elisa: return c.person == .elisa || c.person == .both
            case .cathy: return c.person == .cathy || c.person == .both
            }
        }
    }

    // Frequencies that actually have credits (in display order)
    private var activeFrequencies: [CreditEntry.Frequency] {
        let present = Set(filteredCredits.map(\.frequency))
        return CreditEntry.Frequency.allCases.filter { present.contains($0) }
    }

    // Credits for a given frequency, sorted amount DESC
    private func creditsFor(_ freq: CreditEntry.Frequency) -> [CreditEntry] {
        filteredCredits
            .filter { $0.frequency == freq }
            .sorted { ($0.amountDollars ?? 0) > ($1.amountDollars ?? 0) }
    }

    // Human-readable period label per frequency
    private func periodLabel(for freq: CreditEntry.Frequency) -> String {
        let cal   = Calendar(identifier: .gregorian)
        let month = cal.component(.month, from: Date())
        let year  = cal.component(.year, from: Date())
        let q     = (month - 1) / 3 + 1
        switch freq {
        case .monthly:
            let fmt = DateFormatter(); fmt.dateFormat = "MMMM yyyy"
            return fmt.string(from: Date())
        case .quarterly:   return "Q\(q) \(year)"
        case .semiAnnual:  return month <= 6 ? "H1 \(year)" : "H2 \(year)"
        case .annual:      return "\(year)"
        case .every4Years: return "\(year)"
        }
    }

    var body: some View {
        ZStack {
            Color.sunBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                SerifNavHeader("Credits Tracker")

                // Person filter
                HStack(spacing: 8) {
                    ForEach(PersonFilter.allCases, id: \.self) { pf in
                        filterPill(pf.rawValue, colorHex: "#FBBF24",
                                   active: personFilter == pf) {
                            personFilter = pf
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                if isLoading && credits.isEmpty {
                    Spacer()
                    ProgressView().tint(.sunAccent)
                    Spacer()
                } else if filteredCredits.isEmpty {
                    Spacer()
                    Text("No credits found.")
                        .foregroundStyle(Color.sunSecondary)
                    Spacer()
                } else {
                    List {
                        ForEach(activeFrequencies, id: \.self) { freq in
                            Section {
                                ForEach(creditsFor(freq)) { credit in
                                    creditRow(credit)
                                        .listRowBackground(Color.sunSurface)
                                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                                        .listRowSeparator(.hidden)
                                }
                            } header: {
                                HStack(spacing: 6) {
                                    Text(freq.shortLabel)
                                        .font(.system(size: 11, weight: .bold, design: .serif))
                                        .foregroundStyle(Color(hex: freq.colorHex))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(Color(hex: freq.colorHex).opacity(0.15))
                                        .clipShape(Capsule())
                                        .overlay(Capsule().stroke(Color(hex: freq.colorHex).opacity(0.35), lineWidth: 1))

                                    Text(periodLabel(for: freq))
                                        .font(.system(size: 11, design: .serif))
                                        .foregroundStyle(Color.sunSecondary)
                                }
                                .textCase(nil)
                                .padding(.vertical, 4)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .refreshable { await load(force: true) }
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await load() }
    }

    @ViewBuilder
    private func creditRow(_ credit: CreditEntry) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(credit.credit)
                    .font(.system(size: 15, weight: .semibold, design: .serif))
                    .fontDesign(.serif)
                    .foregroundStyle(Color.sunText)

                HStack(spacing: 6) {
                    CategoryChip(label: credit.card.shortName, colorHex: credit.card.colorHex)
                    CategoryChip(label: credit.person.rawValue,
                                 colorHex: credit.person == .elisa ? "#F472B6" : (credit.person == .cathy ? "#A78BFA" : "#FBBF24"))
                    if let amount = credit.amountDollars {
                        Text("$\(Int(amount))")
                            .font(.system(size: 11, weight: .bold, design: .serif))
                            .foregroundStyle(Color.sunAccent)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.sunAccent.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }
            }

            Spacer()

            if credit.isCurrentPeriodUsed {
                Button { markUnused(credit) } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold, design: .serif))
                        Text("Used")
                            .font(.system(size: 12, weight: .semibold, design: .serif))
                    }
                    .foregroundStyle(Color(hex: "#34D399"))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(hex: "#34D399").opacity(0.15))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color(hex: "#34D399").opacity(0.5), lineWidth: 1))
                }
                .buttonStyle(.plain)
            } else {
                Button { markUsed(credit) } label: {
                    Text("Mark Used")
                        .font(.system(size: 12, weight: .semibold, design: .serif))
                        .foregroundStyle(Color.sunAccent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.sunAccent.opacity(0.15))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.sunAccent.opacity(0.5), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 8)
    }

    private func markUsed(_ credit: CreditEntry) {
        guard let idx = credits.firstIndex(where: { $0.id == credit.id }) else { return }
        applyCurrentPeriod(to: &credits[idx], value: true)
        let updated = credits[idx]
        Task { try? await NotionService.shared.toggleCredit(updated) }
    }

    private func markUnused(_ credit: CreditEntry) {
        guard let idx = credits.firstIndex(where: { $0.id == credit.id }) else { return }
        applyCurrentPeriod(to: &credits[idx], value: false)
        let updated = credits[idx]
        Task { try? await NotionService.shared.toggleCredit(updated) }
    }

    private func applyCurrentPeriod(to credit: inout CreditEntry, value: Bool) {
        let cal        = Calendar(identifier: .gregorian)
        let month      = cal.component(.month, from: Date())
        let q          = (month - 1) / 3 + 1
        let monthNames = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]
        let mName      = monthNames[month - 1]
        let qName      = "Q\(q)"
        switch credit.frequency {
        case .monthly:
            if value { if !credit.monthsUsed.contains(mName)   { credit.monthsUsed.append(mName) } }
            else      { credit.monthsUsed.removeAll   { $0 == mName } }
        case .quarterly:
            if value { if !credit.quartersUsed.contains(qName) { credit.quartersUsed.append(qName) } }
            else      { credit.quartersUsed.removeAll { $0 == qName } }
        case .semiAnnual:
            let halfKey = month <= 6 ? "Q1" : "Q3"
            if value { if !credit.quartersUsed.contains(halfKey) { credit.quartersUsed.append(halfKey) } }
            else      { credit.quartersUsed.removeAll { $0 == halfKey } }
        case .annual, .every4Years:
            credit.yearUsed = value
        }
    }

    private func load(force: Bool = false) async {
        if credits.isEmpty, let cached = NotionService.shared.creditsDiskCache() {
            credits = cached
            isLoading = false
        }
        do {
            credits = try await NotionService.shared.fetchCredits(force: force)
        } catch is CancellationError {
        } catch let err as URLError where err.code == .cancelled {
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func filterPill(_ label: String, colorHex: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: .medium, design: .serif))
                .foregroundStyle(active ? Color.sunBackground : Color(hex: colorHex))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(active ? Color(hex: colorHex) : Color(hex: colorHex).opacity(0.15))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color(hex: colorHex).opacity(active ? 1.0 : 0.35), lineWidth: 1))
                .shadow(color: active ? Color(hex: colorHex).opacity(0.4) : .clear, radius: 6)
        }
        .buttonStyle(.plain)
    }
}
