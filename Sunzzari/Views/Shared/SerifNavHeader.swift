import SwiftUI

// Replacement for SwiftUI's large navigationTitle.
// iOS 26.3 ignores UINavigationBarAppearance entirely (confirmed via pink diagnostic),
// so the only reliable path to a New York serif large title is to hide the native
// nav bar and render our own header inside the view body.
//
// Usage on a pushed view (keeps a back chevron):
//   SerifNavHeader("Restaurants")
//   ...
//   .toolbar(.hidden, for: .navigationBar)
//
// Usage on a root view (no back button):
//   SerifNavHeader("Home", showsBack: false)
struct SerifNavHeader<Trailing: View>: View {
    let title: String
    let showsBack: Bool
    let trailing: Trailing

    @Environment(\.dismiss) private var dismiss

    init(_ title: String, showsBack: Bool = true, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.showsBack = showsBack
        self.trailing = trailing()
    }

    var body: some View {
        VStack(spacing: 0) {
            if showsBack {
                HStack {
                    Button(action: { dismiss() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 17, weight: .semibold))
                            Text("Back")
                                .font(.system(size: 17, weight: .regular, design: .serif))
                        }
                        .foregroundStyle(Color.sunAccent)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }

            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 34, weight: .bold, design: .serif))
                    .foregroundStyle(.white)
                Spacer()
                trailing
            }
            .padding(.horizontal, 16)
            .padding(.top, showsBack ? 6 : 16)
            .padding(.bottom, 8)
        }
    }
}

extension SerifNavHeader where Trailing == EmptyView {
    init(_ title: String, showsBack: Bool = true) {
        self.title = title
        self.showsBack = showsBack
        self.trailing = EmptyView()
    }
}
