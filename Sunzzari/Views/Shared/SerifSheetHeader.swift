import SwiftUI

// Inline-title variant of SerifNavHeader, sized for sheets/forms with
// leading (Cancel) and trailing (Save) buttons.
//
// iOS 26.3 ignores UINavigationBarAppearance, so sheet titles rendered via
// .navigationTitle + ToolbarItem(.principal) cannot be forced into a serif
// font. Use this header inside a sheet body with .toolbar(.hidden, for: .navigationBar).
//
// Usage:
//   SerifSheetHeader("Add Wine",
//       leading: { Button("Cancel") { dismiss() } },
//       trailing: { Button("Save") { save() } })
struct SerifSheetHeader<Leading: View, Trailing: View>: View {
    let title: String
    let leading: Leading
    let trailing: Trailing

    init(_ title: String,
         @ViewBuilder leading: () -> Leading,
         @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.leading = leading()
        self.trailing = trailing()
    }

    var body: some View {
        ZStack {
            HStack {
                leading
                    .font(.system(size: 17, weight: .regular, design: .serif))
                    .foregroundStyle(Color.sunAccent)
                Spacer()
                trailing
                    .font(.system(size: 17, weight: .semibold, design: .serif))
                    .foregroundStyle(Color.sunAccent)
            }
            .padding(.horizontal, 16)

            Text(title)
                .font(.system(size: 17, weight: .semibold, design: .serif))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        .padding(.vertical, 14)
    }
}

extension SerifSheetHeader where Leading == EmptyView {
    init(_ title: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.leading = EmptyView()
        self.trailing = trailing()
    }
}

extension SerifSheetHeader where Trailing == EmptyView {
    init(_ title: String, @ViewBuilder leading: () -> Leading) {
        self.title = title
        self.leading = leading()
        self.trailing = EmptyView()
    }
}

extension SerifSheetHeader where Leading == EmptyView, Trailing == EmptyView {
    init(_ title: String) {
        self.title = title
        self.leading = EmptyView()
        self.trailing = EmptyView()
    }
}
