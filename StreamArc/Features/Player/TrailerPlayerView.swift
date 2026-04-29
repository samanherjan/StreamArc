import StreamArcCore
import SwiftUI
import AVKit

#if !os(tvOS)
import WebKit
#endif

// MARK: - iOS: WKWebView YouTube embed

#if os(iOS)
struct TrailerPlayerView: View {
    let videoId: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            YouTubeWebPlayer(videoId: videoId)
                .ignoresSafeArea()
                .background(Color.black)

            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .foregroundStyle(.white)
                    .shadow(radius: 4)
            }
            .padding()
        }
    }
}

private struct YouTubeWebPlayer: UIViewRepresentable {
    let videoId: String

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsAirPlayForMediaPlayback = true
        config.allowsPictureInPictureMediaPlayback = true
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.scrollView.isScrollEnabled = false
        webView.isOpaque = false
        webView.backgroundColor = .black
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let baseURL = URL(string: "https://www.youtube.com")
        webView.loadHTMLString(youtubeEmbedHTML(videoId: videoId), baseURL: baseURL)
    }
}

// MARK: - macOS: WKWebView YouTube embed

#elseif os(macOS)
struct TrailerPlayerView: View {
    let videoId: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            YouTubeWebPlayerMac(videoId: videoId)
                .ignoresSafeArea()
                .background(Color.black)

            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .foregroundStyle(.white)
                    .shadow(radius: 4)
            }
            .padding()
        }
        .frame(minWidth: 640, minHeight: 360)
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
        let baseURL = URL(string: "https://www.youtube.com")
        webView.loadHTMLString(youtubeEmbedHTML(videoId: videoId), baseURL: baseURL)
    }
}

// MARK: - tvOS: AVPlayer with direct URL from KinoCheck

#else
struct TrailerPlayerView: View {
    let videoId: String
    var directURL: URL? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if let directURL {
            VideoPlayer(player: AVPlayer(url: directURL))
                .ignoresSafeArea()
                .onExitCommand { dismiss() }
        } else {
            // Fallback: use the app's player which handles stream resolution
            PlayerView(streamURL: "https://www.youtube.com/watch?v=\(videoId)", title: "Trailer")
        }
    }
}
#endif

// MARK: - Shared YouTube embed HTML

private func youtubeEmbedHTML(videoId: String) -> String {
    """
    <!DOCTYPE html>
    <html>
    <head>
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <style>
        * { margin: 0; padding: 0; }
        html, body { width: 100%; height: 100%; background: #000; overflow: hidden; }
        iframe { width: 100%; height: 100%; border: none; }
    </style>
    </head>
    <body>
    <iframe src="https://www.youtube.com/embed/\(videoId)?autoplay=1&playsinline=1&rel=0&modestbranding=1"
            allow="autoplay; encrypted-media; picture-in-picture"
            allowfullscreen></iframe>
    </body>
    </html>
    """
}
