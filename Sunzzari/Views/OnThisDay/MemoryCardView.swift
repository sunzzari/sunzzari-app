import SwiftUI

struct MemoryCardView: View {
    let memory: Memory
    @State private var appeared = false

    var body: some View {
        HStack(spacing: 0) {
            // Colored left-edge accent bar matching category
            Rectangle()
                .fill(Color(hex: memory.category.colorHex))
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    CategoryChip(label: memory.category.rawValue,
                                 colorHex: memory.category.colorHex)
                    Spacer()
                    Text(memory.date.formatted(.dateTime.month(.abbreviated).day()) + " · " + String(memory.year))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.sunSecondary)
                }

                Text(memory.title)
                    .font(.system(size: 16, weight: .bold))
                    .fontDesign(.serif)
                    .foregroundStyle(Color.sunText)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if !memory.notes.isEmpty {
                    Text(memory.notes)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.sunSecondary)
                        .lineLimit(3)
                }

                if let photoURL = memory.photoURL {
                    AsyncImageView(urlString: photoURL, cornerRadius: 10)
                        .frame(maxWidth: .infinity)
                        .frame(height: 160)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 10))
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
