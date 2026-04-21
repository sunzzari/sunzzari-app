import SwiftUI

struct DayTimelineView: View {
    let dates: [String]  // yyyy-MM-dd sorted
    @Binding var selectedDate: String?

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
                        let isToday = dateStr == todayString
                        let isSelected = dateStr == selectedDate

                        Button {
                            if selectedDate == dateStr {
                                selectedDate = nil
                            } else {
                                selectedDate = dateStr
                            }
                        } label: {
                            VStack(spacing: 2) {
                                Text(displayString(dateStr))
                                    .font(.system(.caption2, design: .serif, weight: isSelected ? .bold : .medium))

                                if isToday {
                                    Circle()
                                        .fill(Color.sunAccent)
                                        .frame(width: 4, height: 4)
                                }
                            }
                            .foregroundStyle(isSelected ? Color.sunBackground : Color.sunText)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(isSelected ? Color.sunAccent : Color.sunSurface)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .id(dateStr)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
            .onAppear {
                // Auto-scroll to today if present
                if dates.contains(todayString) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        withAnimation { proxy.scrollTo(todayString, anchor: .center) }
                    }
                }
            }
        }
    }

    private func displayString(_ dateStr: String) -> String {
        guard let date = dateFormatter.date(from: dateStr) else { return dateStr }
        return displayFormatter.string(from: date)
    }
}
