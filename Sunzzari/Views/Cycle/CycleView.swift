import SwiftUI

struct CycleView: View {
    @State private var entries: [CycleEntry] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var pendingDate: Date? = nil
    @State private var isSaving = false
    @State private var currentMonth: Date = {
        let cal = Calendar(identifier: .gregorian)
        return cal.date(from: cal.dateComponents([.year, .month], from: Date()))!
    }()

    private let cal = Calendar(identifier: .gregorian)
    /// Assumed period duration in days (no end date stored in DB)
    private let periodLengthDays = 5
    /// How many recent cycles to average over once history exists
    private let avgWindow = 6

    private func defaultAvgCycle(for person: CycleEntry.Person) -> Int {
        switch person {
        case .elisa: return 28
        case .cathy: return 30
        }
    }

    // MARK: - Derived state

    private var latestElisa: CycleEntry? { entries.first(where: { $0.person == .elisa }) }
    private var latestCathy: CycleEntry? { entries.first(where: { $0.person == .cathy }) }

    private var dialogBinding: Binding<Bool> {
        Binding(
            get: { pendingDate != nil },
            set: { if !$0 { pendingDate = nil } }
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.sunBackground.ignoresSafeArea()

                VStack(spacing: 0) {
                    SerifNavHeader("Cycle", showsBack: false)

                    if isLoading && entries.isEmpty {
                        Spacer()
                        ProgressView().tint(.sunAccent)
                        Spacer()
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
                }

                // FAB
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button {
                            pendingDate = Date()
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(.title2, design: .serif, weight: .bold))
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

                if isSaving {
                    Color.black.opacity(0.25).ignoresSafeArea()
                    ProgressView().tint(.sunAccent)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .confirmationDialog(
            "Add period start",
            isPresented: dialogBinding,
            titleVisibility: .visible,
            presenting: pendingDate
        ) { date in
            Button("Add for Elisa") { Task { await quickAdd(person: .elisa, date: date) } }
            Button("Add for Cathy") { Task { await quickAdd(person: .cathy, date: date) } }
            Button("Cancel", role: .cancel) {}
        } message: { date in
            Text(longDateString(date))
        }
        .alert("Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
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
            let weekdays = ["S","M","T","W","T","F","S"]
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 4) {
                ForEach(0..<7, id: \.self) { i in
                    Text(weekdays[i])
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
                            pendingDate = date
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
            if hasPeriod {
                if persons.count == 1 {
                    Color(hex: persons[0].colorHex).opacity(0.45)
                } else {
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
                Color.sunSurface.opacity(0.0)
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
        let latest = latestEntry(for: person)
        return VStack(alignment: .leading, spacing: 8) {
            CategoryChip(label: person.rawValue, colorHex: person.colorHex)

            if latest != nil, let predicted = predictedNext(for: person) {
                let days = max(0, cal.dateComponents([.day], from: cal.startOfDay(for: Date()), to: cal.startOfDay(for: predicted)).day ?? 0)
                Text(shortDateString(predicted))
                    .font(.system(size: 15, weight: .semibold, design: .serif))
                    .fontDesign(.serif)
                    .foregroundStyle(Color.sunText)
                Text("in \(days) day\(days == 1 ? "" : "s")")
                    .font(.system(size: 12, design: .serif))
                    .foregroundStyle(Color.sunSecondary)
                Text("avg \(averageCycle(for: person))d")
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
                Text("Tap any day on the calendar to log a period start.")
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
                            if let length = gapBefore(entry) {
                                Text("\(length)d cycle")
                                    .font(.system(size: 12, design: .serif))
                                    .foregroundStyle(Color.sunSecondary)
                            }
                        }
                        Spacer()
                        if isLatest, let predicted = predictedNext(for: entry.person) {
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

    // MARK: - Cycle math (local source of truth)

    private func latestEntry(for person: CycleEntry.Person) -> CycleEntry? {
        person == .elisa ? latestElisa : latestCathy
    }

    // Computed from the gaps between recent period starts, not the per-entry stored
    // value — the stored field goes stale the moment a new period is logged.
    private func averageCycle(for person: CycleEntry.Person) -> Int {
        let history = entries
            .filter { $0.person == person }
            .sorted { $0.periodStart > $1.periodStart }

        guard history.count >= 2 else { return defaultAvgCycle(for: person) }

        let recent = Array(history.prefix(avgWindow + 1))
        var gaps: [Int] = []
        for i in 0..<(recent.count - 1) {
            let newer = recent[i].periodStart
            let older = recent[i + 1].periodStart
            if let days = cal.dateComponents([.day], from: older, to: newer).day, days > 0 {
                gaps.append(days)
            }
        }
        guard !gaps.isEmpty else { return defaultAvgCycle(for: person) }
        return Int((Double(gaps.reduce(0, +)) / Double(gaps.count)).rounded())
    }

    private func predictedNext(for person: CycleEntry.Person) -> Date? {
        guard let latest = latestEntry(for: person) else { return nil }
        return cal.date(byAdding: .day, value: averageCycle(for: person), to: latest.periodStart)
    }

    private func gapBefore(_ entry: CycleEntry) -> Int? {
        let history = entries
            .filter { $0.person == entry.person }
            .sorted { $0.periodStart > $1.periodStart }
        guard let idx = history.firstIndex(where: { $0.id == entry.id }), idx + 1 < history.count else {
            return nil
        }
        let prev = history[idx + 1].periodStart
        return cal.dateComponents([.day], from: prev, to: entry.periodStart).day
    }

    // MARK: - Calendar data

    private struct DayData {
        var periodPersons:    [CycleEntry.Person] = []
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

        // Predicted next — locally computed from latest entry + per-person avg
        for person in CycleEntry.Person.allCases {
            guard let predicted = predictedNext(for: person) else { continue }
            let key = dayKey(for: predicted)
            if map[key] == nil || map[key]!.periodPersons.isEmpty {
                if !map[key, default: DayData()].predictedPersons.contains(person) {
                    map[key, default: DayData()].predictedPersons.append(person)
                }
            }
        }

        return map
    }

    // MARK: - Save

    private func quickAdd(person: CycleEntry.Person, date: Date) async {
        isSaving = true
        defer { isSaving = false }
        let avg = averageCycle(for: person)
        do {
            let saved = try await NotionService.shared.addCycleEntry(
                person: person,
                periodStart: date,
                avgCycle: avg,
                notes: ""
            )
            // Optimistic insert so the next-period date updates immediately,
            // before Notion's formula columns roundtrip back.
            entries.insert(saved, at: 0)
            entries.sort { $0.periodStart > $1.periodStart }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            // Refresh in background to pick up server-side formula values.
            Task { await load(force: true) }
        } catch {
            errorMessage = error.localizedDescription
        }
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

    private func longDateString(_ date: Date) -> String {
        let fmt = DateFormatter(); fmt.dateFormat = "EEEE, MMMM d"
        return fmt.string(from: date)
    }
}
