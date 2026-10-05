import SwiftUI

/// The one "type a question" bar.
///
/// My Restaurants' "Ask Claude..." and Around Town's search are the same
/// control with a different question behind it, so the bar is written once and
/// each screen passes in what a submit does. The bar knows nothing about where
/// the answer comes from.
struct AskSearchBar: View {
    let placeholder: String
    var icon: String = "sparkles"
    /// Off where the words are names and dishes that autocorrect would mangle.
    var autocorrects = true
    @Binding var text: String
    let isSearching: Bool
    /// True while an answer is on screen, so the clear button stays after the
    /// box has been emptied by hand.
    let hasResults: Bool
    var focused: FocusState<Bool>.Binding
    let onSubmit: () -> Void
    let onClear: () -> Void

    private var isEmpty: Bool { text.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, design: .serif))
                .foregroundStyle(Color.sunAccent)

            TextField(placeholder, text: $text)
                .font(.system(size: 14, design: .serif))
                .foregroundStyle(Color.sunText)
                .focused(focused)
                .submitLabel(.search)
                .autocorrectionDisabled(!autocorrects)
                .onSubmit(onSubmit)

            if isSearching {
                ProgressView().scaleEffect(0.7)
            } else if hasResults || !text.isEmpty {
                Button(action: onClear) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16, design: .serif))
                        .foregroundStyle(Color.sunSecondary)
                }
                .accessibilityLabel("Clear search")
            }

            Button(action: onSubmit) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 20, design: .serif))
                    .foregroundStyle(isEmpty ? Color.sunSecondary : Color.sunAccent)
            }
            .disabled(isEmpty || isSearching)
            .accessibilityLabel("Search")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.sunSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
