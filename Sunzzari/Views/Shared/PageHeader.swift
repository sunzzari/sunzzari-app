import SwiftUI

// Shared header used across top-level tabs so size, font, and padding stay consistent.
struct PageHeader<Trailing: View>: View {
    let title: String
    let trailing: Trailing

    init(_ title: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.system(size: 22, weight: .bold, design: .serif))
                    .fontDesign(.serif)
                    .foregroundStyle(Color.sunText)
                Spacer()
                trailing
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider().background(Color.white.opacity(0.1))
        }
    }
}

extension PageHeader where Trailing == EmptyView {
    init(_ title: String) {
        self.title = title
        self.trailing = EmptyView()
    }
}
