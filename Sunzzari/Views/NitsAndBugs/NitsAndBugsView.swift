import SwiftUI
import UIKit

enum ReportType: String, CaseIterable {
    case nit = "Nit"
    case bug = "Bug"

    var emoji: String {
        switch self {
        case .nit: return "💅"
        case .bug: return "🐞"
        }
    }

    var description: String {
        switch self {
        case .nit: return "Small polish issue or cosmetic thing"
        case .bug: return "Something is broken or wrong"
        }
    }
}

struct NitsAndBugsView: View {
    @State private var reportType: ReportType = .nit
    @State private var title: String = ""
    @State private var details: String = ""
    @State private var submitted = false
    @State private var testSent = false

    private var canSubmit: Bool { !title.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.sunBackground.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {

                        // Type picker
                        VStack(alignment: .leading, spacing: 12) {
                            Text("TYPE")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.sunSecondary)
                                .kerning(1.5)

                            HStack(spacing: 12) {
                                ForEach(ReportType.allCases, id: \.self) { type in
                                    Button {
                                        reportType = type
                                    } label: {
                                        HStack(spacing: 8) {
                                            Text(type.emoji)
                                            Text(type.rawValue)
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(reportType == type ? Color.sunBackground : Color.sunText)
                                        }
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 10)
                                        .frame(maxWidth: .infinity)
                                        .background(reportType == type ? Color.sunAccent : Color.sunSurface)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                    }
                                }
                            }

                            Text(reportType.description)
                                .font(.caption)
                                .foregroundStyle(Color.sunSecondary)
                        }

                        // Title field
                        VStack(alignment: .leading, spacing: 12) {
                            Text("WHAT'S THE ISSUE?")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.sunSecondary)
                                .kerning(1.5)

                            TextField("Short summary", text: $title)
                                .font(.body)
                                .foregroundStyle(Color.sunText)
                                .padding(14)
                                .background(Color.sunSurface)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }

                        // Details field
                        VStack(alignment: .leading, spacing: 12) {
                            Text("DETAILS (OPTIONAL)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.sunSecondary)
                                .kerning(1.5)

                            ZStack(alignment: .topLeading) {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.sunSurface)

                                if details.isEmpty {
                                    Text("Steps to reproduce, screen, context...")
                                        .font(.body)
                                        .foregroundStyle(Color.sunSecondary)
                                        .padding(14)
                                }

                                TextEditor(text: $details)
                                    .font(.body)
                                    .foregroundStyle(Color.sunText)
                                    .scrollContentBackground(.hidden)
                                    .padding(10)
                                    .frame(minHeight: 120)
                            }
                            .frame(minHeight: 120)
                        }

                        // Submit button
                        Button {
                            sendReport()
                        } label: {
                            HStack(spacing: 8) {
                                Text(reportType.emoji)
                                Text("Send \(reportType.rawValue)")
                                    .font(.headline)
                                    .foregroundStyle(Color.sunBackground)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(canSubmit ? Color.sunAccent : Color.sunSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .disabled(!canSubmit)

                        if submitted {
                            Text("Sent! Your mail app should have opened.")
                                .font(.caption)
                                .foregroundStyle(Color.sunSecondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                        }

                        Divider()
                            .background(Color.white.opacity(0.1))
                            .padding(.vertical, 4)

                        // Test notification
                        VStack(alignment: .leading, spacing: 12) {
                            Text("TEST NOTIFICATION")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.sunSecondary)
                                .kerning(1.5)

                            Button {
                                Task { await NotificationService.shared.sendTestNotification() }
                                testSent = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { testSent = false }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "bell.fill")
                                    Text(testSent ? "Background the app now →" : "Fire in 5 sec")
                                        .font(.headline)
                                        .foregroundStyle(Color.sunBackground)
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(testSent ? Color.green.opacity(0.8) : Color.sunSurface)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                                )
                            }

                            Text("Fires a sample \"Best Moments\" notification. Background the app to see it.")
                                .font(.caption)
                                .foregroundStyle(Color.sunSecondary)
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Nits & Bugs")
            .navigationBarTitleDisplayMode(.large)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }

    private func sendReport() {
        let device = UIDevice.current
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"

        let bodyText = """
        \(reportType.rawValue.uppercased()): \(title)

        \(details.isEmpty ? "(no details)" : details)

        ---
        App: Sunzzari \(appVersion) (\(build))
        Device: \(device.model) — iOS \(device.systemVersion)
        """

        let subject = "Sunzzari \(reportType.rawValue): \(title)"
        let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let encodedBody = bodyText.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlString = "mailto:elisafazzari815@gmail.com?subject=\(encodedSubject)&body=\(encodedBody)"

        if let url = URL(string: urlString) {
            UIApplication.shared.open(url)
            submitted = true
            title = ""
            details = ""
        }
    }
}
