import SwiftUI
import WebKit

/// Full-screen viewer for a trip's itinerary page (served from
/// elisa-travel-map).
///
/// Loads the live URL rather than a cached HTML string. That page became a
/// filterable map on 2026-09-06, so it needs its JavaScript; re-rendering a
/// saved copy with `loadHTMLString` would show a dead page with no map and no
/// working filters. The old "open it once and it is cached here" promise went
/// with it, and saying it would now be a lie.
///
/// Offline is `TripTodayView`'s job: it is native, it caches the trip to disk,
/// and it has its own map.
struct ItineraryWebView: View {
    let urlString: String

    @Environment(\.dismiss) private var dismiss
    @State private var loading = true
    @State private var failed = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.sunBackground.ignoresSafeArea()

                if let url = URL(string: urlString), !failed {
                    ItineraryWebRepresentable(url: url, isLoading: $loading, didFail: $failed)
                        .ignoresSafeArea(edges: .bottom)
                } else if failed {
                    // Dropping the old offline message when this became a live
                    // URL left a blank screen with no explanation. Say what is
                    // wrong and point at the screen that does work offline.
                    VStack(spacing: 10) {
                        Image(systemName: "wifi.slash")
                            .font(.title)
                            .foregroundStyle(Color.sunSecondary)
                        Text("The full itinerary needs a connection")
                            .font(.system(.subheadline, design: .serif))
                            .foregroundStyle(Color.sunText)
                        Text("It is a live map, so it cannot be cached. Today's plan works offline - go back and use the day view.")
                            .font(.system(.caption, design: .serif))
                            .foregroundStyle(Color.sunSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                } else {
                    Text("That itinerary link is not a valid URL.")
                        .font(.system(.subheadline, design: .serif))
                        .foregroundStyle(Color.sunSecondary)
                }

                if loading {
                    ProgressView().tint(Color.sunAccent)
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
    }
}

private struct ItineraryWebRepresentable: UIViewRepresentable {
    let url: URL
    @Binding var isLoading: Bool
    @Binding var didFail: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(isLoading: $isLoading, didFail: $didFail, host: url.host)
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // Loaded once in makeUIView; the page revalidates itself server-side.
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        @Binding var isLoading: Bool
        @Binding var didFail: Bool
        private let host: String?

        init(isLoading: Binding<Bool>, didFail: Binding<Bool>, host: String?) {
            _isLoading = isLoading
            _didFail = didFail
            self.host = host
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isLoading = false
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            isLoading = false
            didFail = true
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            isLoading = false
            didFail = true
        }

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // Keep in-app navigation inside the page (day and type filters are
            // client-side, so they never navigate). Send anything that leaves
            // our own host - Google Maps directions links - to the system.
            if navigationAction.navigationType == .linkActivated,
               let target = navigationAction.request.url,
               target.host != host {
                UIApplication.shared.open(target)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}
