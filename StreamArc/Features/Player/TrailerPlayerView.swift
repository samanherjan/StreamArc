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
/// Uses multiple fallback strategies to maximize compatibility.
enum YouTubeStreamExtractor {
    static func extractStreamURL(videoId: String) async -> String? {
        // Strategy 1: Embed page scraping (most reliable, no API key needed)
        if let url = await extractFromEmbedPage(videoId: videoId) {
            return url
        }
        // Strategy 2: iOS client innertube API
        if let url = await extractFromInnertube(videoId: videoId, clientName: "IOS", clientVersion: "19.29.1") {
            return url
        }
        // Strategy 3: TV embedded client
        if let url = await extractFromInnertube(videoId: videoId, clientName: "TVHTML5_SIMPLY_EMBEDDED_PLAYER", clientVersion: "2.0") {
            return url
        }
        return nil
    }

    /// Scrapes the YouTube embed page to extract the player response JSON containing stream URLs.
    private static func extractFromEmbedPage(videoId: String) async -> String? {
        guard let url = URL(string: "https://www.youtube.com/embed/\(videoId)") else { return nil }

        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue(
            "Mozilla/5.0 (Apple TV; U; CPU AppleTV5,3 OS 17.0 like Mac OS X; en-us) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )

        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let html = String(data: data, encoding: .utf8) else { return nil }

        // Extract ytInitialPlayerResponse or playerResponse from the embed page
        // Pattern: var ytInitialPlayerResponse = {...};
        let patterns = [
            #"ytInitialPlayerResponse\s*=\s*(\{.+?\});"#,
            #"\"playerResponse\"\s*:\s*\"(.+?)\""#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
                  let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)) else { continue }

            if match.numberOfRanges >= 2,
               let range = Range(match.range(at: 1), in: html) {
                var jsonStr = String(html[range])

                // If it's an escaped JSON string, unescape it
                if jsonStr.contains("\\u0026") {
                    jsonStr = jsonStr.replacingOccurrences(of: "\\u0026", with: "&")
                    jsonStr = jsonStr.replacingOccurrences(of: "\\\"", with: "\"")
                    jsonStr = jsonStr.replacingOccurrences(of: "\\/", with: "/")
                }

                if let jsonData = jsonStr.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                   let streamURL = extractBestStream(from: json) {
                    return streamURL
                }
            }
        }

        // Alternative: look for streamingData directly in the page
        if let streamRange = html.range(of: #""streamingData""#) {
            // Find the enclosing JSON by looking for the ytInitialPlayerResponse block
            let searchArea = String(html[html.startIndex..<html.endIndex])
            if let startIdx = searchArea.range(of: "ytInitialPlayerResponse")?.lowerBound {
                // Find first { after =
                let afterEquals = searchArea[startIdx...]
                if let braceStart = afterEquals.firstIndex(of: "{") {
                    // Extract balanced JSON
                    if let jsonStr = extractBalancedJSON(from: searchArea, startingAt: braceStart),
                       let jsonData = jsonStr.data(using: .utf8),
                       let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                       let url = extractBestStream(from: json) {
                        return url
                    }
                }
            }
        }

        return nil
    }

    /// Uses YouTube's innertube API with specified client context.
    private static func extractFromInnertube(videoId: String, clientName: String, clientVersion: String) async -> String? {
        guard let apiURL = URL(string: "https://www.youtube.com/youtubei/v1/player?key=AIzaSyA8eiZmM1FaDVjRy-df2KTyQ_vz_yYM39w&prettyPrint=false") else { return nil }

        var request = URLRequest(url: apiURL, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let userAgent: String
        switch clientName {
        case "IOS":
            userAgent = "com.google.ios.youtube/19.29.1 (iPhone16,2; U; CPU iOS 17_5_1 like Mac OS X;)"
        case "TVHTML5_SIMPLY_EMBEDDED_PLAYER":
            userAgent = "Mozilla/5.0 (SMART-TV; LINUX; Tizen 6.5)"
        default:
            userAgent = "Mozilla/5.0"
        }
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        var clientContext: [String: Any] = [
            "clientName": clientName,
            "clientVersion": clientVersion,
            "hl": "en",
            "gl": "US"
        ]
        if clientName == "TVHTML5_SIMPLY_EMBEDDED_PLAYER" {
            clientContext["clientScreen"] = "EMBED"
        }

        var body: [String: Any] = [
            "videoId": videoId,
            "context": ["client": clientContext]
        ]
        if clientName == "TVHTML5_SIMPLY_EMBEDDED_PLAYER" {
            body["thirdParty"] = ["embedUrl": "https://www.youtube.com"]
        }

        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        request.httpBody = httpBody

        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        return extractBestStream(from: json)
    }

    /// Extracts the best playable stream URL from a YouTube player response JSON.
    private static func extractBestStream(from json: [String: Any]) -> String? {
        guard let streamingData = json["streamingData"] as? [String: Any] else { return nil }

        // Try HLS manifest first (best for Apple platforms — native AVPlayer support)
        if let hlsUrl = streamingData["hlsManifestUrl"] as? String {
            return hlsUrl
        }

        // Progressive formats (MP4 with audio+video combined)
        if let formats = streamingData["formats"] as? [[String: Any]] {
            let mp4Formats = formats
                .filter { ($0["mimeType"] as? String)?.contains("video/mp4") == true }
                .filter { $0["url"] as? String != nil }  // Skip formats needing signature decryption
                .sorted { ($0["height"] as? Int ?? 0) > ($1["height"] as? Int ?? 0) }

            // Prefer 720p for good quality without excessive bandwidth
            let preferred = mp4Formats.first { ($0["height"] as? Int ?? 0) <= 720 }
                ?? mp4Formats.first
            if let best = preferred, let url = best["url"] as? String {
                return url
            }
        }

        // Adaptive formats (video-only MP4, still watchable)
        if let adaptiveFormats = streamingData["adaptiveFormats"] as? [[String: Any]] {
            let videoFormats = adaptiveFormats
                .filter { ($0["mimeType"] as? String)?.contains("video/mp4") == true }
                .filter { $0["url"] as? String != nil }
                .sorted { ($0["height"] as? Int ?? 0) > ($1["height"] as? Int ?? 0) }

            let preferred = videoFormats.first { ($0["height"] as? Int ?? 0) <= 720 }
                ?? videoFormats.first
            if let best = preferred, let url = best["url"] as? String {
                return url
            }
        }

        return nil
    }

    /// Extracts a balanced JSON object string starting from a given index.
    private static func extractBalancedJSON(from str: String, startingAt: String.Index) -> String? {
        var depth = 0
        var endIdx = startingAt
        for idx in str[startingAt...].indices {
            let ch = str[idx]
            if ch == "{" { depth += 1 }
            else if ch == "}" {
                depth -= 1
                if depth == 0 {
                    endIdx = str.index(after: idx)
                    return String(str[startingAt..<endIdx])
                }
            }
            // Safety: don't scan more than 500KB
            if str.distance(from: startingAt, to: idx) > 500_000 { break }
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
