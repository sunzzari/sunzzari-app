import SwiftUI
import WebKit

/// Full-screen viewer for a trip's live itinerary page (served from
/// elisa-travel-map). Fetches the HTML, caches it to disk for offline viewing,
/// and renders it in a WKWebView. Map links (Google Maps) open externally.
struct ItineraryWebView: View {
    let urlString: String

    @Environment(\.dismiss) private var dismiss
    @State private var html: String?
    @State private var loading = true

    var body: some View {
        NavigationStack {
            ZStack {
                Color.sunBackground.ignoresSafeArea()

                if let html {
                    ItineraryWebRepresentable(html: html, baseURL: URL(string: urlString))
                        .ignoresSafeArea(edges: .bottom)
                } else if loading {
                    ProgressView().tint(Color.sunAccent)
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "wifi.slash")
                            .font(.title)
                            .foregroundStyle(Color.sunSecondary)
                        Text("Itinerary unavailable offline")
                            .font(.system(.subheadline, design: .serif))
                            .foregroundStyle(Color.sunSecondary)
                        Text("Open it once with a connection and it will be cached here.")
                            .font(.system(.caption, design: .serif))
                            .foregroundStyle(Color.sunSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                }
            }
            .navigationTitle("Itinerary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(Color.sunSurface, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.sunAccent)
                }
            }
        }
        .task {
            html = await TravelService.shared.fetchItineraryHTML(urlString: urlString)
            loading = false
        }
    }
}

private struct ItineraryWebRepresentable: UIViewRepresentable {
    let html: String
    let baseURL: URL?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.loadHTMLString(html, baseURL: baseURL)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // Content is loaded once in makeUIView; nothing to refresh here.
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // The initial loadHTMLString is .other; let it through. Any tapped
            // link (map pins -> Google Maps) opens in the system browser/Maps.
            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}
