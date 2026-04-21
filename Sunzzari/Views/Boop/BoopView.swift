import SwiftUI
import UIKit

// Sheet surface for custom boops. The 6 primary presets live as one-tap tiles on Home.
struct BoopView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var customText = ""
    @State private var isSending = false
    @State private var errorText: String? = nil

    private var trimmed: String {
        customText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Write a custom boop")
                        .font(.system(.subheadline, design: .serif))
                        .foregroundStyle(Color.sunSecondary)

                    TextField("Write something sweet...", text: $customText, axis: .vertical)
                        .lineLimit(4, reservesSpace: true)
                        .foregroundStyle(Color.sunText)
                        .padding(12)
                        .background(Color.sunSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(
                                    trimmed.isEmpty
                                        ? Color.white.opacity(0.08)
                                        : Color.sunAccent,
                                    lineWidth: 1
                                )
                        )

                    if let errorText {
                        Text(errorText)
                            .font(.system(.caption, design: .serif))
                            .foregroundStyle(.red)
                    }

                    Button {
                        Task { await sendBoop() }
                    } label: {
                        HStack(spacing: 8) {
                            if isSending {
                                ProgressView()
                                    .tint(Color.sunBackground)
                                    .scaleEffect(0.85)
                            }
                            Text(isSending ? "Sending..." : "Boop! 👉")
                                .font(.system(.headline, design: .serif))
                                .fontWeight(.bold)
                                .foregroundStyle(Color.sunBackground)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 17)
                        .background(
                            trimmed.isEmpty
                                ? Color.sunSecondary.opacity(0.4)
                                : Color.sunAccent
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .shadow(
                            color: trimmed.isEmpty
                                ? .clear
                                : Color.sunAccent.opacity(0.45),
                            radius: 10, x: 0, y: 4
                        )
                        .animation(.easeOut(duration: 0.15), value: trimmed.isEmpty)
                    }
                    .disabled(trimmed.isEmpty || isSending)
                }
                .padding(20)
            }
            .background(Color.sunBackground)
            .navigationTitle("Custom Boop")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.sunSecondary)
                }
            }
        }
    }

    private func sendBoop() async {
        let message = trimmed
        guard !message.isEmpty else { return }
        isSending = true
        errorText = nil
        do {
            try await BoopService.shared.send(message: message)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            dismiss()
        } catch {
            errorText = "Couldn't send — try again."
        }
        isSending = false
    }
}
