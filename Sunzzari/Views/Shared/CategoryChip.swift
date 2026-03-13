import SwiftUI

struct CategoryChip: View {
    let label: String
    let colorHex: String
    var isSelected: Bool = false

    var body: some View {
        Text(label.uppercased())
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(isSelected ? Color.sunBackground : Color(hex: colorHex))
            .tracking(0.8)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                isSelected
                    ? Color(hex: colorHex)
                    : Color(hex: colorHex).opacity(0.18)
            )
            .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}
