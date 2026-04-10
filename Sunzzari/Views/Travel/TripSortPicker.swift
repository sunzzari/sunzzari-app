import SwiftUI

enum TripSortMode: String, CaseIterable {
    case type     = "Type"
    case date     = "Date"
    case priority = "Priority"
}

struct TripSortPicker: View {
    @Binding var sortMode: TripSortMode
    let nearMeActive: Bool

    var body: some View {
        Menu {
            if nearMeActive {
                Text("Distance (Near Me active)")
            } else {
                ForEach(TripSortMode.allCases, id: \.self) { mode in
                    Button {
                        sortMode = mode
                    } label: {
                        HStack {
                            Text(mode.rawValue)
                            if mode == sortMode {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.up.arrow.down")
                Text(nearMeActive ? "Distance" : sortMode.rawValue)
            }
            .font(.caption2.weight(.medium))
            .foregroundStyle(Color.sunText)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.sunSurface)
            .clipShape(Capsule())
        }
    }
}
