import StreamArcCore
import SwiftUI

struct TrailerButton: View {
    let item: VODItem
    @Environment(EntitlementManager.self) private var entitlements
    @State private var showPaywall = false
    @State private var showTrailer = false
    @State private var isLoading = false
    @State private var videoId: String?
    @State private var showNotFound = false

    var body: some View {
        Button {
            guard entitlements.isPremium else {
                showPaywall = true
                return
            }
            Task { await findAndPlay() }
        } label: {
            HStack(spacing: 6) {
                if isLoading {
                    ProgressView().tint(.white).scaleEffect(0.8)
                } else {
                    Image(systemName: entitlements.isPremium ? "play.fill" : "lock.fill")
                }
                Text("Trailer")
            }
            .font(.subheadline.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Color.saAccent.opacity(entitlements.isPremium ? 1.0 : 0.5))
            .clipShape(Capsule())
        }
        .disabled(isLoading)
        .paywallSheet(isPresented: $showPaywall)
        .sheet(isPresented: $showTrailer) {
            if let videoId {
                TrailerPlayerView(videoId: videoId)
            }
        }
        .alert("Trailer Not Found", isPresented: $showNotFound) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Could not find a trailer for \"\(item.title)\".")
        }
    }

    private func findAndPlay() async {
        isLoading = true
        defer { isLoading = false }

        let query: String
        if item.type == .series {
            query = "\(item.title) official trailer"
        } else {
            let yearStr = item.year.map { " \($0)" } ?? ""
            query = "\(item.title)\(yearStr) official trailer"
        }

        videoId = await YouTubeSearch.findFirstVideoId(query: query)
        if videoId != nil {
            showTrailer = true
        } else {
            showNotFound = true
        }
    }
}

// MARK: - YouTube search (extracts video ID from search page HTML)

enum YouTubeSearch {
    static func findFirstVideoId(query: String) async -> String? {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://www.youtube.com/results?search_query=\(encoded)") else {
            return nil
        }

        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")

        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let html = String(data: data, encoding: .utf8) else {
            return nil
        }

        // YouTube embeds video IDs in the page as "videoId":"XXXXXXXXXXX"
        // Find the first one that appears in search results
        return extractVideoId(from: html)
    }

    private static func extractVideoId(from html: String) -> String? {
        // Pattern 1: "videoId":"VIDEO_ID" (from JSON data in page)
        let pattern1 = #""videoId"\s*:\s*"([a-zA-Z0-9_-]{11})""#
        if let match = html.range(of: pattern1, options: .regularExpression) {
            let substring = html[match]
            // Extract the 11-char ID
            let idPattern = #"[a-zA-Z0-9_-]{11}"#
            // Find last occurrence which is the actual ID
            if let idRange = substring.range(of: idPattern, options: [.regularExpression, .backwards]) {
                return String(substring[idRange])
            }
        }

        // Pattern 2: /watch?v=VIDEO_ID
        let pattern2 = #"/watch\?v=([a-zA-Z0-9_-]{11})"#
        if let match = html.range(of: pattern2, options: .regularExpression) {
            let substring = html[match]
            let idPattern = #"[a-zA-Z0-9_-]{11}$"#
            if let idRange = substring.range(of: idPattern, options: .regularExpression) {
                return String(substring[idRange])
            }
        }

        return nil
    }
}

struct PremiumBadgeView: View {
    var label: String = "PRO"

    var body: some View {
        Text(label)
            .font(.system(size: 9, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Color.saAccent)
            .clipShape(Capsule())
    }
}
