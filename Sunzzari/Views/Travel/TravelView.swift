import SwiftUI
import SafariServices
import UIKit

struct TravelView: View {
    @State private var showSafari = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.sunBackground.ignoresSafeArea()

                VStack(spacing: 32) {
                    Spacer()

                    // Hero icon
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.sunAccent.opacity(0.3), Color.sunAccent.opacity(0.05)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 140, height: 140)

                        Image(systemName: "airplane.circle.fill")
                            .font(.system(size: 72))
                            .foregroundStyle(Color.sunAccent)
                    }

                    // Text content
                    VStack(spacing: 12) {
                        Text("Our Travel Map")
                            .font(.largeTitle.weight(.bold))
                            .foregroundStyle(Color.sunText)

                        Text("Every place we've been, every adventure we've taken — all pinned on the map.")
                            .font(.subheadline)
                            .foregroundStyle(Color.sunSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }

                    // Open button
                    Button {
                        showSafari = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "map.fill")
                            Text("Open Travel Map")
                                .font(.headline)
                        }
                        .foregroundStyle(Color.sunBackground)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.sunAccent)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal, 32)
                    }

                    Spacer()
                    Spacer()
                }
            }
            .navigationTitle("✈️ Travel")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Color.sunBackground, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .sheet(isPresented: $showSafari) {
            SafariView(url: Constants.Travel.mapURL)
                .ignoresSafeArea()
        }
    }


}

// MARK: - Safari wrapper
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        let vc = SFSafariViewController(url: url, configuration: config)
        vc.preferredControlTintColor = UIColor(Color.sunAccent)
        vc.preferredBarTintColor = UIColor(Color.sunBackground)
        return vc
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
