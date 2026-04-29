import Foundation

/// Platform-agnostic stream URL resolution and retry logic.
/// This lives in the core package — no AVKit/UIKit dependencies.
public struct StreamResolver: Sendable {

    public enum ResolvedStream: Sendable {
        case direct(URL)
        case stalkerResolved(URL)
    }

    /// Resolves the final playable URL from a raw stream URL string.
    /// - Strips "ffmpeg " prefix from Stalker/portal URLs
    /// - Resolves Stalker cmd URLs via the portal's create_link API
    public static func resolve(
        urlString: String,
        sourceType: SourceType,
        stalkerConfig: StalkerClient.Config? = nil
    ) async throws -> URL {
        var cleaned = urlString

        // Strip common "ffmpeg " prefix from Stalker/portal URLs
        if cleaned.hasPrefix("ffmpeg ") {
            cleaned = String(cleaned.dropFirst(7))
        }

        // Stalker sources need server-side link creation
        if sourceType == .stalker, let config = stalkerConfig {
            let client = StalkerClient(config: config)
            do {
                try await client.authenticate()
                let resolved = try await client.resolveStreamURL(cmd: cleaned)
                let final = resolved.hasPrefix("ffmpeg ") ? String(resolved.dropFirst(7)) : resolved
                guard let url = URL(string: final) else { throw URLError(.badURL) }
                return url
            } catch {
                // If resolution fails, try the raw URL as fallback
                print("[StreamResolver] Stalker resolve failed, trying raw URL: \(error)")
            }
        }

        guard let url = URL(string: cleaned) else { throw URLError(.badURL) }
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

    /// Returns the delay for the given attempt (0-indexed).
    public func delay(forAttempt attempt: Int) -> TimeInterval {
        min(baseDelay * pow(2.0, Double(attempt)), maxDelay)
    }
}
