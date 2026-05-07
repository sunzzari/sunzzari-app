import SwiftUI

struct DayTimelineView: View {
    let dates: [String]  // yyyy-MM-dd sorted
    @Binding var selectedDate: String?

    @State private var pulseOn = false

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private let displayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    private var todayString: String {
        dateFormatter.string(from: Date())
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(dates, id: \.self) { dateStr in
                        chip(for: dateStr)
                            .id(dateStr)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
            .onAppear {
                pulseOn = true
                if dates.contains(todayString) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        withAnimation { proxy.scrollTo(todayString, anchor: .center) }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func chip(for dateStr: String) -> some View {
        let isToday = dateStr == todayString
        let isSelected = dateStr == selectedDate

        Button {
            selectedDate = (selectedDate == dateStr) ? nil : dateStr
        } label: {
            Text(displayString(dateStr))
                .font(.system(.caption2, design: .serif, weight: isSelected ? .bold : .medium))
                .foregroundStyle(isSelected ? Color.sunBackground : Color.sunText)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(chipBackground(isToday: isToday, isSelected: isSelected))
                .overlay(chipBorder(isToday: isToday, isSelected: isSelected))
                .clipShape(Capsule())
                .overlay(alignment: .topTrailing) {
                    if isToday && !isSelected {
                        Circle()
                            .fill(Color.sunAccent)
                            .frame(width: 6, height: 6)
                            .scaleEffect(pulseOn ? 1.0 : 0.6)
                            .opacity(pulseOn ? 1.0 : 0.5)
                            .animation(
                                .easeInOut(duration: 1.0).repeatForever(autoreverses: true),
                                value: pulseOn
                            )
                            .offset(x: 3, y: -3)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    private func chipBackground(isToday: Bool, isSelected: Bool) -> some View {
        Capsule().fill(
            isSelected
            ? Color.sunAccent
            : (isToday ? Color.sunAccent.opacity(0.15) : Color.sunSurface)
        )
    }

    @ViewBuilder
    private func chipBorder(isToday: Bool, isSelected: Bool) -> some View {
        if isToday && !isSelected {
            Capsule().stroke(Color.sunAccent.opacity(0.5), lineWidth: 1)
        } else {
            Capsule().stroke(Color.clear, lineWidth: 0)
        }
    }

    private func displayString(_ dateStr: String) -> String {
        guard let date = dateFormatter.date(from: dateStr) else { return dateStr }
        return displayFormatter.string(from: date)
    }
}
