import Foundation

/// Platform-agnostic stream URL resolution and retry logic.
/// This lives in the core package — no AVKit/UIKit dependencies.
public struct StreamResolver: Sendable {

    public enum ResolvedStream: Sendable {
        case direct(URL)
        case stalkerResolved(URL)
    }

    /// Resolves the final playable URL from a raw stream URL string.
    ///
    /// Processing order:
    ///  1. Strip "ffmpeg " prefix
    ///  2. Strip pipe-style HTTP header suffixes (e.g. `url|User-Agent=VLC`)
    ///  3. For Stalker sources: resolve via create_link (or return direct HTTP URL as-is)
    ///  4. Percent-encode any illegal characters
    ///  5. Validate the result has an http/https scheme — never return a schemeless URL
    public static func resolve(
        urlString: String,
        sourceType: SourceType,
        stalkerConfig: StalkerClient.Config? = nil
    ) async throws -> URL {
        var cleaned = urlString

        // Strip common "ffmpeg " prefix
        if cleaned.hasPrefix("ffmpeg ") {
            cleaned = String(cleaned.dropFirst(7))
        }

        // Strip pipe-style HTTP headers (e.g. "url|User-Agent=VLC&Referer=...")
        if let pipeRange = cleaned.range(of: "|") {
            cleaned = String(cleaned[cleaned.startIndex..<pipeRange.lowerBound])
        }

        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        // ── Stalker: server-side URL resolution ──────────────────────────────
        // IMPORTANT: Do NOT fall back to the raw cmd on failure. A raw Stalker
        // cmd is either a base64 JSON blob or an opaque string — neither is a
        // valid HTTP URL. Swallowing the error and passing it to AVFoundation
        // produces a schemeless URL that always fails with "Cannot Open".
        if sourceType == .stalker, let config = stalkerConfig {
            let client = StalkerClient(config: config)
            try await client.authenticate()
            let resolved = try await client.resolveStreamURL(cmd: cleaned)
            let final = resolved.hasPrefix("ffmpeg ") ? String(resolved.dropFirst(7)) : resolved
            return try validatedHTTPURL(from: final)
        }

        // ── Direct / M3U / Xtream / Enigma2 ─────────────────────────────────
        if let url = URL(string: cleaned), url.scheme != nil {
            return url
        }

        // Percent-encode illegal characters while preserving URL structure
        let legal = CharacterSet.urlQueryAllowed
            .union(.urlHostAllowed)
            .union(.urlPathAllowed)
            .union(.urlFragmentAllowed)
            .union(CharacterSet(charactersIn: ":/?#[]@!$&'()*+,;=-._~%"))

        if let encoded = cleaned.addingPercentEncoding(withAllowedCharacters: legal),
           let url = URL(string: encoded), url.scheme != nil {
            return url
        }

        throw URLError(.badURL)
    }

    // MARK: - Helpers

    /// Returns a URL only if it has an http or https scheme. Throws URLError(.badURL) otherwise.
    /// This guard prevents schemeless base64 blobs from reaching AVFoundation.
    private static func validatedHTTPURL(from string: String) throws -> URL {
        guard !string.isEmpty,
              let url = URL(string: string),
              let scheme = url.scheme,
              scheme == "http" || scheme == "https" else {
            throw URLError(.badURL)
        }
        return url
    }
}

/// Retry policy with exponential backoff for stream playback.
public struct RetryPolicy: Sendable {
    public let maxAttempts: Int
    public let baseDelay: TimeInterval
    public let maxDelay: TimeInterval

    public init(maxAttempts: Int = 3, baseDelay: TimeInterval = 1.0, maxDelay: TimeInterval = 8.0) {
        self.maxAttempts = maxAttempts
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
    }

    public func delay(forAttempt attempt: Int) -> TimeInterval {
        min(baseDelay * pow(2.0, Double(attempt)), maxDelay)
    }
}
