import SwiftUI

struct BestOfDetailView: View {
    let entry: BestOfEntry
    let namespace: Namespace.ID
    let onDismiss: () -> Void
    var onEdit: (() -> Void)? = nil

    var body: some View {
        ZStack {
            // Tap background to dismiss
            Color.clear
                .contentShape(Rectangle())
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            VStack {
                Spacer()

                // Expanded card — matches geometry with the list card
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top) {
                        CategoryChip(label: entry.category.rawValue, colorHex: entry.category.colorHex)
                        Spacer()
                        if let onEdit {
                            Button {
                                onDismiss()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { onEdit() }
                            } label: {
                                Image(systemName: "pencil")
                                    .font(.system(size: 12, weight: .bold, design: .serif))
                                    .foregroundStyle(Color.sunAccent)
                                    .frame(width: 28, height: 28)
                                    .background(Color.sunBackground.opacity(0.9))
                                    .clipShape(Circle())
                            }
                        }
                        Button { onDismiss() } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .bold, design: .serif))
                                .foregroundStyle(Color.sunSecondary)
                                .frame(width: 28, height: 28)
                                .background(Color.sunBackground.opacity(0.9))
                                .clipShape(Circle())
                        }
                    }

                    Text(entry.entry)
                        .font(.system(size: 26, weight: .bold, design: .serif))
                        .foregroundStyle(Color.sunText)

                    if !entry.isUnassigned {
                        Text(entry.isYearOnly
                             ? String(entry.year)
                             : entry.date.formatted(.dateTime.month(.wide).day().year()))
                            .font(.system(size: 13, weight: .medium, design: .serif))
                            .foregroundStyle(Color.sunAccent)
                    }

                    if !entry.notes.isEmpty {
                        Color.sunBackground.opacity(0.4).frame(height: 0.5)
                        Text(entry.notes)
                            .font(.system(size: 15, design: .serif))
                            .foregroundStyle(Color.sunSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.sunSurface)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .matchedGeometryEffect(id: entry.id, in: namespace)
                .padding(.horizontal, 16)

                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
