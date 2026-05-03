import Foundation

/// Shared session manager that holds exactly one `StalkerClient` per unique portal URL.
///
/// All callers — `StreamResolver`, `StalkerContentService`, `SeriesDetailView`, etc. —
/// MUST obtain their client through this manager so that:
///   • The token is shared and never re-fetched unnecessarily.
///   • The URLSession and its cookie storage are reused across all requests.
///   • The token TTL is enforced in one place.
public actor StalkerSessionManager {

    public static let shared = StalkerSessionManager()
    private init() {}

    /// One client per portal URL (keyed by normalised portal URL + MAC).
    private var clients: [String: StalkerClient] = [:]

    /// Returns the shared `StalkerClient` for the given config, creating it if necessary.
    /// If a client for this portal already exists but uses a different MAC address,
    /// the old client is replaced and its token is invalidated.
    public func client(for config: StalkerClient.Config) -> StalkerClient {
        let key = cacheKey(config)
        if let existing = clients[key] {
            return existing
        }
        let newClient = StalkerClient(config: config)
        clients[key] = newClient
        return newClient
    }

    /// Removes the cached client for this config (e.g. after portal settings change).
    public func invalidate(config: StalkerClient.Config) {
        let key = cacheKey(config)
        clients.removeValue(forKey: key)
    }

    private nonisolated func cacheKey(_ config: StalkerClient.Config) -> String {
        "\(config.portalURL)|\(config.macAddress)"
    }
}
