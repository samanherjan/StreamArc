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
// tvOS — Play YouTube trailer directly via stream URL extraction + KSPlayer
struct TrailerPlayerView: View {
    let videoId: String
    @Environment(\.dismiss) private var dismiss
    @State private var streamURL: String?
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        if let streamURL, !streamURL.isEmpty {
            PlayerView(streamURL: streamURL, title: "Trailer")
        } else {
            ZStack {
                Color.saBackground.ignoresSafeArea()

                if isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                            .tint(Color.saAccent)
                            .scaleEffect(2)
                        Text("Loading trailer…")
                            .font(.body)
                            .foregroundStyle(Color.saTextSecondary)
                    }
                } else if let error {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.red)
                        Text(error)
                            .font(.body)
                            .foregroundStyle(Color.saTextSecondary)
                            .multilineTextAlignment(.center)
                        Button("Dismiss") { dismiss() }
                            .buttonStyle(.borderedProminent)
                            .tint(Color.saAccent)
                    }
                    .padding(.horizontal, 80)
                }
            }
            .task { await resolveTrailerURL() }
        }
    }

    private func resolveTrailerURL() async {
        isLoading = true
        defer { isLoading = false }

        if let url = await YouTubeStreamExtractor.extractStreamURL(videoId: videoId) {
            streamURL = url
        } else {
            error = "Could not load trailer. The video may be restricted."
        }
    }
}

/// Extracts a direct playable stream URL from a YouTube video ID.
/// Uses YouTube's `get_video_info` / innertube API to get stream URLs without auth.
enum YouTubeStreamExtractor {
    static func extractStreamURL(videoId: String) async -> String? {
        // Use YouTube's innertube API (same as yt-dlp's android client approach)
        let apiURL = URL(string: "https://www.youtube.com/youtubei/v1/player?prettyPrint=false")!

        var request = URLRequest(url: apiURL, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(
            "Mozilla/5.0 (Linux; Android 12) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )

        // Use the Android client context — it returns direct URLs without DASH/DRM for most videos
        let body: [String: Any] = [
            "videoId": videoId,
            "context": [
                "client": [
                    "clientName": "ANDROID",
                    "clientVersion": "19.09.37",
                    "androidSdkVersion": 30,
                    "hl": "en",
                    "gl": "US"
                ]
            ]
        ]

        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        request.httpBody = httpBody

        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        // Extract streaming data
        guard let streamingData = json["streamingData"] as? [String: Any] else { return nil }

        // Try progressive formats first (single file MP4 — best for playback)
        if let formats = streamingData["formats"] as? [[String: Any]] {
            // Pick the highest quality MP4 with both audio+video
            let mp4Formats = formats
                .filter { ($0["mimeType"] as? String)?.contains("video/mp4") == true }
                .sorted { ($0["height"] as? Int ?? 0) > ($1["height"] as? Int ?? 0) }

            if let best = mp4Formats.first, let url = best["url"] as? String {
                return url
            }
        }

        // Fallback: adaptive formats (video-only, but still playable)
        if let adaptiveFormats = streamingData["adaptiveFormats"] as? [[String: Any]] {
            let videoFormats = adaptiveFormats
                .filter { ($0["mimeType"] as? String)?.contains("video/mp4") == true }
                .sorted { ($0["height"] as? Int ?? 0) > ($1["height"] as? Int ?? 0) }

            // Prefer 720p or lower for faster loading
            let preferred = videoFormats.first { ($0["height"] as? Int ?? 0) <= 720 }
                ?? videoFormats.first

            if let best = preferred, let url = best["url"] as? String {
                return url
            }
        }

        // Try HLS manifest if available
        if let hlsUrl = streamingData["hlsManifestUrl"] as? String {
            return hlsUrl
        }

        return nil
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
