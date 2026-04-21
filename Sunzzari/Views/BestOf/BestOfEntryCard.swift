import SwiftUI

struct BestOfEntryCard: View {
    let entry: BestOfEntry
    @State private var appeared = false

    var body: some View {
        HStack(spacing: 0) {
            // Colored left-edge accent bar matching category
            Rectangle()
                .fill(Color(hex: entry.category.colorHex))
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    CategoryChip(label: entry.category.rawValue, colorHex: entry.category.colorHex)
                    Spacer()
                    if !entry.isUnassigned {
                        Text(entry.isYearOnly
                             ? String(entry.year)
                             : entry.date.formatted(.dateTime.month(.abbreviated).year()))
                            .font(.system(size: 11, weight: .medium, design: .serif))
                            .foregroundStyle(Color.sunSecondary)
                    }
                }

                Text(entry.entry)
                    .font(.system(size: 16, weight: .bold, design: .serif))
                    .fontDesign(.serif)
                    .foregroundStyle(Color.sunText)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if !entry.notes.isEmpty {
                    Text(entry.notes)
                        .font(.system(size: 13, design: .serif))
                        .foregroundStyle(Color.sunSecondary)
                        .lineLimit(2)
                }
            }
            .padding(16)
        }
        .background(Color.sunSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 12)
        .onAppear {
            withAnimation(.easeOut(duration: 0.35)) {
                appeared = true
            }
        }
    }
}
