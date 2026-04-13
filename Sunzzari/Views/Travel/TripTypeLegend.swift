import SwiftUI

struct TripTypeLegend: View {
    @Binding var activeTypes: Set<TripItem.ItemType>

    private var anyActive: Bool { !activeTypes.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Filter type")
                .font(.caption2.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(Color.sunSecondary)

            ForEach(TripItem.ItemType.allCases, id: \.self) { type in
                let isActive = activeTypes.contains(type)
                let dimmed = anyActive && !isActive

                Button {
                    if isActive {
                        activeTypes.remove(type)
                    } else {
                        activeTypes.insert(type)
                    }
                } label: {
                    HStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(Color(hex: type.colorHex))
                                .frame(width: 22, height: 22)
                            if isActive {
                                Circle()
                                    .stroke(Color(hex: type.colorHex), lineWidth: 2)
                                    .frame(width: 28, height: 28)
                            }
                            Image(systemName: type.sfSymbol)
                                .font(.system(size: 10))
                                .foregroundStyle(.white)
                        }
                        .frame(width: 30, height: 30)

                        Text(type.rawValue)
                            .font(.caption)
                            .fontWeight(isActive ? .semibold : .medium)
                    }
                    .foregroundStyle(Color.sunText)
                    .opacity(dimmed ? 0.3 : 1.0)
                }
                .buttonStyle(.plain)
            }

            if anyActive {
                Button {
                    activeTypes.removeAll()
                } label: {
                    Text("Clear")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Color.sunAccent)
                        .underline()
                }
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .environment(\.colorScheme, .dark)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.3), radius: 6)
    }
}
