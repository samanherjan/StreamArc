import StreamArcCore
import SwiftUI

#if os(iOS)
import WebKit

struct TrailerPlayerView: View {
    let videoId: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            YouTubeWebPlayer(videoId: videoId)
                .ignoresSafeArea()
                .background(Color.black)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                            .foregroundStyle(.white)
                    }
                }
        }
    }
}

private struct YouTubeWebPlayer: UIViewRepresentable {
    let videoId: String

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.scrollView.isScrollEnabled = false
        webView.isOpaque = false
        webView.backgroundColor = .black
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        webView.loadHTMLString(youtubeHTML(videoId: videoId), baseURL: nil)
    }
}

#elseif os(macOS)
import WebKit

struct TrailerPlayerView: View {
    let videoId: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            YouTubeWebPlayerMac(videoId: videoId)
                .ignoresSafeArea()
                .background(Color.black)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                            .foregroundStyle(.white)
                    }
                }
        }
    }
}

private struct YouTubeWebPlayerMac: NSViewRepresentable {
    let videoId: String

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = []
        let webView = WKWebView(frame: .zero, configuration: config)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        webView.loadHTMLString(youtubeHTML(videoId: videoId), baseURL: nil)
    }
}

#else
// tvOS — WKWebView not available
struct TrailerPlayerView: View {
    let videoId: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(Color.saAccent)
                Text("Watch Trailer on YouTube")
                    .font(.title3.bold())
                    .foregroundStyle(Color.saTextPrimary)
                Text("Trailers open in the YouTube app on Apple TV.")
                    .font(.body)
                    .foregroundStyle(Color.saTextSecondary)
                    .multilineTextAlignment(.center)
                Button("Open in YouTube") {
                    if let url = URL(string: "youtube://watch/\(videoId)") {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.saAccent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.saBackground)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

#endif

// MARK: - Shared HTML template

private func youtubeHTML(videoId: String) -> String {
    """
    <!DOCTYPE html>
    <html>
    <head>
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <style>
        * { margin: 0; padding: 0; }
        html, body { width: 100%; height: 100%; background: #000; }
        iframe { width: 100%; height: 100%; border: none; }
    </style>
    </head>
    <body>
    <iframe src="https://www.youtube.com/embed/\(videoId)?autoplay=1&playsinline=1&rel=0"
            allow="autoplay; encrypted-media" allowfullscreen></iframe>
    </body>
    </html>
    """
}
