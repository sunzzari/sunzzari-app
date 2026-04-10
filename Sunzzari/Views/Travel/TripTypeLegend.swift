import SwiftUI

struct TripTypeLegend: View {
    @Binding var activeTypes: Set<TripItem.ItemType>
    @Binding var isVisible: Bool

    var body: some View {
        if isVisible {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(TripItem.ItemType.allCases, id: \.self) { type in
                    Button {
                        if activeTypes.contains(type) {
                            activeTypes.remove(type)
                        } else {
                            activeTypes.insert(type)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color(hex: type.colorHex))
                                .frame(width: 10, height: 10)
                            Image(systemName: type.sfSymbol)
                                .font(.caption2)
                            Text(type.rawValue)
                                .font(.caption2)
                        }
                        .foregroundStyle(
                            activeTypes.isEmpty || activeTypes.contains(type)
                                ? Color.sunText
                                : Color.sunSecondary.opacity(0.5)
                        )
                    }
                    .buttonStyle(.plain)
                }

                if !activeTypes.isEmpty {
                    Button {
                        activeTypes.removeAll()
                    } label: {
                        Text("Clear")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(Color.sunAccent)
                    }
                    .padding(.top, 2)
                }
            }
            .padding(10)
            .background(Color.sunSurface.opacity(0.95))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .shadow(color: .black.opacity(0.2), radius: 4)
        }
    }
}
