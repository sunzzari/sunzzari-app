import SwiftUI

struct CategoryChip: View {
    let label: String
    let colorHex: String
    var isSelected: Bool = false

    var body: some View {
        Text(label)
            .font(.system(size: 11, weight: .medium, design: .serif))
            .foregroundStyle(isSelected ? Color.sunBackground : Color(hex: colorHex))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                isSelected
                    ? Color(hex: colorHex)
                    : Color(hex: colorHex).opacity(0.12)
            )
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color(hex: colorHex).opacity(isSelected ? 1 : 0.35), lineWidth: 1))
            .shadow(color: isSelected ? Color(hex: colorHex).opacity(0.4) : .clear, radius: 6, y: 0)
    }
}
