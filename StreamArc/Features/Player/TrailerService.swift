import StreamArcCore
import Foundation

/// Service that fetches trailer information using TMDB + KinoCheck APIs.
/// - iOS/macOS: returns a YouTube video key for WKWebView embed
/// - tvOS: returns a direct .mp4 URL via KinoCheck for AVPlayer
actor TrailerService {
    static let shared = TrailerService()

    /// Returns the YouTube video key (e.g. "dQw4w9WgXcQ") for embed playback.
    func fetchYouTubeKey(for item: VODItem, apiKey: String) async -> String? {
        // Use the provided key, falling back to APIKeys.tmdb
        let key = apiKey.isEmpty ? APIKeys.tmdb : apiKey
        return await TMDBClient.shared.youtubeTrailerKey(for: item, apiKey: key)
    }

    /// Returns a direct .mp4 trailer URL from KinoCheck (for tvOS AVPlayer).
    /// Flow: TMDB search → get IMDb ID → KinoCheck API → direct URL.
    func fetchDirectTrailerURL(for item: VODItem, apiKey: String) async -> URL? {
        let key = apiKey.isEmpty ? APIKeys.tmdb : apiKey

        // First try to get IMDb ID via TMDB
        guard let imdbId = await TMDBClient.shared.imdbId(for: item, apiKey: key),
              !imdbId.isEmpty else { return nil }

        // Query KinoCheck for a direct trailer URL
        return await fetchFromKinoCheck(imdbId: imdbId)
    }

    /// Queries the KinoCheck API for a direct .mp4 trailer URL.
    private func fetchFromKinoCheck(imdbId: String) async -> URL? {
        guard let apiURL = URL(string: "https://api.kinocheck.com/movies?imdb_id=\(imdbId)&language=en") else { return nil }

        var request = URLRequest(url: apiURL, timeoutInterval: 10)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else { return nil }

        // KinoCheck returns a JSON object with trailer info
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        // Try to get the trailer URL from the response
        // KinoCheck response has "trailer" object with "url" field for direct mp4
        if let trailer = json["trailer"] as? [String: Any],
           let urlStr = trailer["url"] as? String,
           let url = URL(string: urlStr) {
            return url
        }

        // Alternative: check "videos" array
        if let videos = json["videos"] as? [[String: Any]] {
            for video in videos {
                if let urlStr = video["url"] as? String,
                   urlStr.hasSuffix(".mp4") || urlStr.contains("mp4"),
                   let url = URL(string: urlStr) {
                    return url
                }
            }
        }

        return nil
    }
}
