import SwiftUI

struct CycleView: View {
    @State private var entries: [CycleEntry] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showAddSheet = false
    @State private var preselectedDate: Date = Date()
    @State private var currentMonth: Date = {
        let cal = Calendar(identifier: .gregorian)
        return cal.date(from: cal.dateComponents([.year, .month], from: Date()))!
    }()

    private let cal = Calendar(identifier: .gregorian)
    /// Assumed period duration in days (no end date stored in DB)
    private let periodLengthDays = 5

    // MARK: - Derived state

    private var latestElisa: CycleEntry? { entries.first(where: { $0.person == .elisa }) }
    private var latestCathy: CycleEntry?  { entries.first(where: { $0.person == .cathy  }) }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.sunBackground.ignoresSafeArea()

                if isLoading && entries.isEmpty {
                    ProgressView().tint(.sunAccent)
                } else {
                    ScrollView {
                        VStack(spacing: 20) {
                            calendarSection
                            nextPeriodSummary
                            recentEntriesSection
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 100)
                    }
                    .refreshable { await load(force: true) }
                }

                // FAB
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button {
                            preselectedDate = Date()
                            showAddSheet = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.title2.weight(.bold))
                                .foregroundStyle(Color.sunBackground)
                                .padding(18)
                                .background(Color.sunAccent)
                                .clipShape(Circle())
                                .shadow(color: Color.sunAccent.opacity(0.5), radius: 12)
                        }
                        .padding(.trailing, 20)
                        .padding(.bottom, 24)
                    }
                }
            }
            .navigationTitle("Cycle")
            .navigationBarTitleDisplayMode(.large)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(Color.sunSurface, for: .navigationBar)
        }
        .sheet(isPresented: $showAddSheet, onDismiss: { Task { await load(force: true) } }) {
            AddCycleEntryView(defaultDate: preselectedDate, entries: entries)
        }
        .task { await load() }
    }

    // MARK: - Calendar

    private var calendarSection: some View {
        VStack(spacing: 12) {
            // Month navigation
            HStack {
                Button { navigateMonth(-1) } label: {
                    Image(systemName: "chevron.left")
                        .foregroundStyle(Color.sunAccent)
                        .padding(8)
                }
                Spacer()
                Text(monthYearString(for: currentMonth))
                    .font(.system(size: 16, weight: .semibold, design: .serif))
                    .fontDesign(.serif)
                    .foregroundStyle(Color.sunText)
                Spacer()
                Button { navigateMonth(1) } label: {
                    Image(systemName: "chevron.right")
                        .foregroundStyle(Color.sunAccent)
                        .padding(8)
                }
            }

            // Weekday headers
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 4) {
                ForEach(["S","M","T","W","T","F","S"], id: \.self) { d in
                    Text(d)
                        .font(.system(size: 11, weight: .medium, design: .serif))
                        .foregroundStyle(Color.sunSecondary)
                        .frame(maxWidth: .infinity)
                }
            }

            // Day cells
            let calData  = buildCalendarData()
            let offset   = firstWeekdayOffset(of: currentMonth)
            let numDays  = daysInMonth(currentMonth)
            let total    = offset + numDays

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 4) {
                ForEach(0..<total, id: \.self) { index in
                    if index < offset {
                        Color.clear.frame(height: 44)
                    } else {
                        let day    = index - offset + 1
                        let date   = dateFor(day: day, in: currentMonth)
                        let isToday = cal.isDateInToday(date)
                        let data   = calData[dayKey(for: date)] ?? DayData()

                        Button {
                            preselectedDate = date
                            showAddSheet = true
                        } label: {
                            VStack(spacing: 2) {
                                dayCell(day: day, isToday: isToday, data: data)
                                // Predicted dot(s) below number
                                HStack(spacing: 2) {
                                    ForEach(data.predictedPersons, id: \.self) { person in
                                        Circle()
                                            .fill(Color(hex: person.colorHex).opacity(0.45))
                                            .frame(width: 4, height: 4)
                                    }
                                }
                                .frame(height: 6)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Legend
            HStack(spacing: 16) {
                legendItem(color: CycleEntry.Person.elisa.colorHex, label: "Elisa")
                legendItem(color: CycleEntry.Person.cathy.colorHex, label: "Cathy")
                legendItem(color: "#FFFFFF", label: "Predicted", opacity: 0.35)
                Spacer()
            }
            .padding(.top, 4)
        }
        .padding(16)
        .background(Color.sunSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func dayCell(day: Int, isToday: Bool, data: DayData) -> some View {
        let hasPeriod = !data.periodPersons.isEmpty
        let persons   = data.periodPersons

        ZStack {
            // Period background
            if hasPeriod {
                if persons.count == 1 {
                    Color(hex: persons[0].colorHex).opacity(0.45)
                } else {
                    // Both Elisa + Cathy — diagonal split
                    LinearGradient(
                        colors: [
                            Color(hex: CycleEntry.Person.elisa.colorHex).opacity(0.45),
                            Color(hex: CycleEntry.Person.cathy.colorHex).opacity(0.45)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            } else if isToday {
                Color.sunSurface.opacity(0.0) // handled by border below
            }

            Text("\(day)")
                .font(.system(size: 13, weight: hasPeriod || isToday ? .semibold : .regular, design: .serif))
                .foregroundStyle(hasPeriod ? Color.white : (isToday ? Color.sunAccent : Color.sunText))
        }
        .frame(width: 28, height: 28)
        .clipShape(Circle())
        .overlay(isToday ? Circle().stroke(Color.sunAccent, lineWidth: 1.5) : nil)
    }

    private func legendItem(color: String, label: String, opacity: Double = 0.45) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color(hex: color).opacity(opacity))
                .frame(width: 8, height: 8)
            Text(label)
                .font(.system(size: 10, design: .serif))
                .foregroundStyle(Color.sunSecondary)
        }
    }

    // MARK: - Next Period Summary

    private var nextPeriodSummary: some View {
        HStack(spacing: 12) {
            ForEach(CycleEntry.Person.allCases, id: \.self) { person in
                summaryCard(for: person)
            }
        }
    }

    private func summaryCard(for person: CycleEntry.Person) -> some View {
        let latest = person == .elisa ? latestElisa : latestCathy
        return VStack(alignment: .leading, spacing: 8) {
            CategoryChip(label: person.rawValue, colorHex: person.colorHex)

            if let entry = latest {
                if let predicted = entry.predictedNext {
                    let days = max(0, cal.dateComponents([.day], from: Date(), to: predicted).day ?? 0)
                    Text(shortDateString(predicted))
                        .font(.system(size: 15, weight: .semibold, design: .serif))
                        .fontDesign(.serif)
                        .foregroundStyle(Color.sunText)
                    Text("in \(days) day\(days == 1 ? "" : "s")")
                        .font(.system(size: 12, design: .serif))
                        .foregroundStyle(Color.sunSecondary)
                } else {
                    Text("No prediction")
                        .font(.system(size: 13, design: .serif))
                        .foregroundStyle(Color.sunSecondary)
                }
                Text("avg \(entry.avgCycle)d")
                    .font(.system(size: 11, design: .serif))
                    .foregroundStyle(Color.sunSecondary)
            } else {
                Text("No data yet")
                    .font(.system(size: 13, design: .serif))
                    .foregroundStyle(Color.sunSecondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.sunSurface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Recent Entries

    private var recentEntriesSection: some View {
        let latestElisaID = latestElisa?.id
        let latestCathyID = latestCathy?.id

        return VStack(alignment: .leading, spacing: 8) {
            Text("Recent")
                .font(.system(size: 13, weight: .semibold, design: .serif))
                .foregroundStyle(Color.sunSecondary)

            if entries.isEmpty {
                Text("No entries yet. Tap + to add your first period start.")
                    .font(.system(size: 14, design: .serif))
                    .foregroundStyle(Color.sunSecondary)
                    .padding(.top, 4)
            } else {
                ForEach(entries.prefix(10)) { entry in
                    let isLatest = entry.id == latestElisaID || entry.id == latestCathyID
                    HStack(spacing: 10) {
                        CategoryChip(label: entry.person.rawValue, colorHex: entry.person.colorHex)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(shortDateString(entry.periodStart))
                                .font(.system(size: 14, weight: .medium, design: .serif))
                                .foregroundStyle(Color.sunText)
                            if let length = entry.cycleLength {
                                Text("\(length)d cycle")
                                    .font(.system(size: 12, design: .serif))
                                    .foregroundStyle(Color.sunSecondary)
                            }
                        }
                        Spacer()
                        // Only show "Next" for the most recent entry per person
                        if isLatest, let predicted = entry.predictedNext {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("Next")
                                    .font(.system(size: 10, design: .serif))
                                    .foregroundStyle(Color.sunSecondary)
                                Text(shortDateString(predicted))
                                    .font(.system(size: 12, weight: .medium, design: .serif))
                                    .foregroundStyle(Color.sunAccent)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.sunSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    // MARK: - Calendar data

    private struct DayData {
        var periodPersons:   [CycleEntry.Person] = []
        var predictedPersons: [CycleEntry.Person] = []
    }

    private func buildCalendarData() -> [String: DayData] {
        var map: [String: DayData] = [:]

        // Mark all days in every confirmed period range
        for entry in entries {
            for offset in 0..<periodLengthDays {
                guard let date = cal.date(byAdding: .day, value: offset, to: entry.periodStart) else { continue }
                let key = dayKey(for: date)
                if !map[key, default: DayData()].periodPersons.contains(entry.person) {
                    map[key, default: DayData()].periodPersons.append(entry.person)
                }
            }
        }

        // Predicted next — only from the most recent entry per person
        for latest in [latestElisa, latestCathy].compactMap({ $0 }) {
            guard let predicted = latest.predictedNext else { continue }
            let key = dayKey(for: predicted)
            // Only show predicted dot if that day isn't already a confirmed period day
            if map[key] == nil || map[key]!.periodPersons.isEmpty {
                if !map[key, default: DayData()].predictedPersons.contains(latest.person) {
                    map[key, default: DayData()].predictedPersons.append(latest.person)
                }
            }
        }

        return map
    }

    // MARK: - Helpers

    private func load(force: Bool = false) async {
        if entries.isEmpty, let cached = NotionService.shared.cycleDiskCache() {
            entries = cached
            isLoading = false
        }
        do {
            entries = try await NotionService.shared.fetchCycleEntries(force: force)
        } catch is CancellationError {
        } catch let err as URLError where err.code == .cancelled {
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func dayKey(for date: Date) -> String {
        let c = cal.dateComponents([.year, .month, .day], from: date)
        return "\(c.year!)-\(c.month!)-\(c.day!)"
    }

    private func firstWeekdayOffset(of month: Date) -> Int {
        let first = cal.date(from: cal.dateComponents([.year, .month], from: month))!
        return cal.component(.weekday, from: first) - 1
    }

    private func daysInMonth(_ month: Date) -> Int {
        cal.range(of: .day, in: .month, for: month)!.count
    }

    private func dateFor(day: Int, in month: Date) -> Date {
        var comps = cal.dateComponents([.year, .month], from: month)
        comps.day = day
        return cal.date(from: comps)!
    }

    private func navigateMonth(_ delta: Int) {
        if let next = cal.date(byAdding: .month, value: delta, to: currentMonth) {
            currentMonth = next
        }
    }

    private func monthYearString(for date: Date) -> String {
        let fmt = DateFormatter(); fmt.dateFormat = "MMMM yyyy"
        return fmt.string(from: date)
    }

    private func shortDateString(_ date: Date) -> String {
        let fmt = DateFormatter(); fmt.dateFormat = "MMM d"
        return fmt.string(from: date)
    }
}
