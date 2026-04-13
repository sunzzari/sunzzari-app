import SwiftUI

private let boopPresets: [String] = [
    "Thinking of you 🥰",
    "Come cuddle me 🫶",
    "I love you 💛",
    "Miss you! 🦕",
    "BAAAAAABE 🌟",
    "HIIIIIIIIII 👋",
    "Feed me 🍜",
    "HUMMINGBIRD NEEDS A BRANCH 🌿",
    "poop 💩",
    "Coming to rub your butt 🍑",
    "KIIIIISSSSSSS 💋",
    "🤘",
]

struct BoopView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var customText = ""
    @State private var selectedPreset: String? = nil
    @State private var isSending = false
    @State private var showSuccess = false
    @State private var showError = false

    private var messageToSend: String? {
        let trimmed = customText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return selectedPreset
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    // Subtitle
                    Text("Pick a preset or write your own")
                        .font(.subheadline)
                        .foregroundStyle(Color.sunSecondary)
                        .padding(.horizontal, 20)

                    // Preset grid
                    LazyVGrid(
                        columns: [GridItem(.flexible()), GridItem(.flexible())],
                        spacing: 10
                    ) {
                        ForEach(boopPresets, id: \.self) { preset in
                            Button {
                                selectedPreset = preset
                                customText = ""
                            } label: {
                                Text(preset)
                                    .font(.callout)
                                    .foregroundStyle(
                                        selectedPreset == preset
                                            ? Color.sunBackground
                                            : Color.sunText
                                    )
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 14)
                                    .frame(maxWidth: .infinity, minHeight: 68)
                                    .background(
                                        selectedPreset == preset
                                            ? Color.sunAccent
                                            : Color.sunSurface
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(
                                                selectedPreset == preset
                                                    ? Color.sunAccent
                                                    : Color.white.opacity(0.08),
                                                lineWidth: 1
                                            )
                                    )
                                    .animation(.easeOut(duration: 0.15), value: selectedPreset)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)

                    // Custom field
                    VStack(alignment: .leading, spacing: 8) {
                        Text("CUSTOM")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.sunSecondary)
                            .tracking(1.5)

                        TextField("Write something sweet...", text: $customText, axis: .vertical)
                            .lineLimit(3, reservesSpace: true)
                            .foregroundStyle(Color.sunText)
                            .padding(12)
                            .background(Color.sunSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(
                                        customText.isEmpty
                                            ? Color.white.opacity(0.08)
                                            : Color.sunAccent,
                                        lineWidth: 1
                                    )
                            )
                            .onChange(of: customText) { _, newValue in
                                if !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    selectedPreset = nil
                                }
                            }
                    }
                    .padding(.horizontal, 20)

                    // Send button
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
                                .font(.headline)
                                .fontWeight(.bold)
                                .foregroundStyle(Color.sunBackground)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 17)
                        .background(
                            messageToSend == nil
                                ? Color.sunSecondary.opacity(0.4)
                                : Color.sunAccent
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .shadow(
                            color: messageToSend == nil
                                ? .clear
                                : Color.sunAccent.opacity(0.45),
                            radius: 10, x: 0, y: 4
                        )
                        .animation(.easeOut(duration: 0.15), value: messageToSend == nil)
                    }
                    .disabled(messageToSend == nil || isSending)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 32)
                }
                .padding(.top, 16)
            }
            .background(Color.sunBackground)
            .navigationTitle("Boop")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.sunSecondary)
                }
            }
            .alert("Boop sent! 💛", isPresented: $showSuccess) {
                Button("Yay!") { dismiss() }
            } message: {
                Text("Your boop is on its way.")
            }
            .alert("Send failed", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Couldn't send the boop. Check your connection and try again.")
            }
        }
    }

    private func sendBoop() async {
        guard let message = messageToSend else { return }
        isSending = true
        do {
            try await BoopService.shared.send(message: message)
            showSuccess = true
        } catch {
            showError = true
        }
        isSending = false
    }
}
