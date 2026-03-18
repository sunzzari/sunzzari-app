import SwiftUI
import UIKit

struct BatterySlider: View {
    @Binding var value: Int   // 0–100
    let isEditable: Bool
    let onCommit: (Int) -> Void

    @State private var dragValue: CGFloat = 0
    @State private var isDragging = false
    @GestureState private var dragOffset: CGFloat = 0

    private let trackHeight: CGFloat = 36
    private let haptic = UIImpactFeedbackGenerator(style: .light)

    var body: some View {
        VStack(spacing: 6) {
            // Emoji + percentage row
            HStack {
                Text(moodEmoji)
                    .font(.title3)
                Spacer()
            }

            // Track
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Background track
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.1))
                        .frame(height: trackHeight)

                    // Fill bar
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(hex: fillColorHex))
                        .frame(width: fillWidth(in: geo.size.width), height: trackHeight)
                        .animation(.easeOut(duration: 0.1), value: value)

                    // Percentage label centered
                    Text("\(value)%")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                }
                .frame(height: trackHeight)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .gesture(isEditable ? dragGesture(width: geo.size.width) : nil)
            }
            .frame(height: trackHeight)
        }
    }

    // MARK: - Computed

    private var fillColorHex: String {
        switch value {
        case 0...20:  return "#EF4444"
        case 21...40: return "#F97316"
        case 41...60: return "#FBBF24"
        case 61...80: return "#22C55E"
        default:      return "#16A34A"
        }
    }

    private var moodEmoji: String {
        switch value {
        case 0...20:  return "😴"
        case 21...40: return "😔"
        case 41...60: return "😊"
        case 61...80: return "🌟"
        default:      return "🔥"
        }
    }

    private func fillWidth(in totalWidth: CGFloat) -> CGFloat {
        max(0, min(totalWidth, totalWidth * CGFloat(value) / 100))
    }

    // MARK: - Gesture

    private func dragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { gesture in
                let raw = gesture.location.x / width
                let clamped = max(0, min(1, raw))
                let newValue = Int(clamped * 100)
                if newValue != value {
                    haptic.impactOccurred()
                }
                value = newValue
            }
            .onEnded { gesture in
                let raw = gesture.location.x / width
                let clamped = max(0, min(1, raw))
                let finalValue = Int(clamped * 100)
                value = finalValue
                onCommit(finalValue)
            }
    }
}
