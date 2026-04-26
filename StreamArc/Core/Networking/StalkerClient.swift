import Foundation

// MAG / Stalker Middleware HTTP client.
// Authentication uses MAC address; a session token is obtained on handshake
// and must be refreshed each session.
public actor StalkerClient {

    public struct Config: Sendable {
        public let portalURL: String  // e.g. "http://portal.example.com:8080/stalker_portal/c/"
        public let macAddress: String // e.g. "00:1A:79:XX:XX:XX"

        public init(portalURL: String, macAddress: String) {
            self.portalURL = portalURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            self.macAddress = macAddress
        }

        fileprivate var serverBase: String {
            // normalise: strip /c and append /server
            let base = portalURL.hasSuffix("/c")
                ? String(portalURL.dropLast(2))
                : portalURL
            return "\(base)/server"
        }
    }

    private let config: Config
    private let session: URLSession
    private var token: String?

    public init(config: Config, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    // MARK: - Authentication

    /// Performs the two-step handshake and stores the session token.
    public func authenticate() async throws {
        // Step 1: load.php → get initial token
        let loadURL = "\(config.serverBase)/load.php"
        let loadData = try await get(loadURL)
        guard let loadJSON = try? JSONSerialization.jsonObject(with: loadData) as? [String: Any],
              let jsToken = loadJSON["js"] as? [String: Any],
              let tok = jsToken["token"] as? String else {
            throw StalkerError.tokenNotFound
        }

        // Step 2: handshake.php → exchange MAC + token for auth token
        let handshakeURL = "\(config.serverBase)/handshake.php"
        let handshakeData = try await get(handshakeURL, extraHeaders: [
            "Cookie": "mac=\(config.macAddress); stb_lang=en; timezone=UTC",
            "Authorization": "Bearer \(tok)"
        ])
        guard let hsJSON = try? JSONSerialization.jsonObject(with: handshakeData) as? [String: Any],
              let jsAuth = hsJSON["js"] as? [String: Any],
              let authToken = jsAuth["token"] as? String else {
            throw StalkerError.handshakeFailed
        }

        self.token = authToken
    }

    // MARK: - Channel list

    public func channels() async throws -> [Channel] {
        let tok = try requireToken()
        let url = "\(config.serverBase)/itv.php?action=get_all_channels"
        let data = try await get(url, authToken: tok)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let jsData = json["js"] as? [String: Any],
              let dataArr = jsData["data"] as? [[String: Any]] else {
            return []
        }

        return dataArr.compactMap { dict -> Channel? in
            guard let id = dict["id"] as? String ?? (dict["id"] as? Int).map({ "\($0)" }),
                  let name = dict["name"] as? String else { return nil }
            let cmd = dict["cmd"] as? String ?? ""
            let logo = dict["logo"] as? String
            return Channel(id: id, name: name, logoURL: logo, streamURL: cmd)
        }
    }

    // MARK: - VOD categories

    public func vodCategories() async throws -> [[String: Any]] {
        let tok = try requireToken()
        let url = "\(config.serverBase)/vod.php?action=get_categories"
        let data = try await get(url, authToken: tok)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let js = json["js"] as? [[String: Any]] else { return [] }
        return js
    }

    public func vodItems(categoryId: String) async throws -> [VODItem] {
        let tok = try requireToken()
        let url = "\(config.serverBase)/vod.php?action=get_ordered_list&category=\(categoryId)&p=1&items_per_page=1000"
        let data = try await get(url, authToken: tok)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let js = json["js"] as? [String: Any],
              let dataArr = js["data"] as? [[String: Any]] else { return [] }

        return dataArr.compactMap { dict -> VODItem? in
            guard let id = dict["id"] as? String ?? (dict["id"] as? Int).map({ "\($0)" }),
                  let name = dict["name"] as? String,
                  let cmd = dict["cmd"] as? String else { return nil }
            return VODItem(
                id: id,
                title: name,
                posterURL: dict["screenshot_uri"] as? String,
                streamURL: cmd,
                type: .movie
            )
        }
    }

    // MARK: - Stream URL resolution

    public func resolveStreamURL(cmd: String) async throws -> String {
        let tok = try requireToken()
        let encoded = cmd.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? cmd
        let url = "\(config.serverBase)/vod.php?action=create_link&cmd=\(encoded)&series=0"
        let data = try await get(url, authToken: tok)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let js = json["js"] as? [String: Any],
              let cmd2 = js["cmd"] as? String else {
            throw StalkerError.streamResolutionFailed
        }
        // Remove "ffmpeg " prefix if present
        return cmd2.hasPrefix("ffmpeg ") ? String(cmd2.dropFirst(7)) : cmd2
    }

    // MARK: - Networking

    private func get(_ urlString: String, authToken: String? = nil, extraHeaders: [String: String] = [:]) async throws -> Data {
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.setValue(config.macAddress, forHTTPHeaderField: "X-User-ID")
        request.setValue(config.macAddress, forHTTPHeaderField: "X-Device-ID")
        if let tok = authToken {
            request.setValue("Bearer \(tok)", forHTTPHeaderField: "Authorization")
            request.setValue("mac=\(config.macAddress); stb_lang=en; timezone=UTC", forHTTPHeaderField: "Cookie")
        }
        for (k, v) in extraHeaders { request.setValue(v, forHTTPHeaderField: k) }
        let (data, _) = try await session.data(for: request)
        return data
    }

    private func requireToken() throws -> String {
        guard let tok = token else { throw StalkerError.notAuthenticated }
        return tok
    }
}

public enum StalkerError: Error, LocalizedError {
    case notAuthenticated
    case tokenNotFound
    case handshakeFailed
    case streamResolutionFailed

    public var errorDescription: String? {
        switch self {
        case .notAuthenticated:       return "Not authenticated — call authenticate() first"
        case .tokenNotFound:          return "Could not retrieve session token"
        case .handshakeFailed:        return "Handshake failed — check portal URL and MAC address"
        case .streamResolutionFailed: return "Could not resolve stream URL"
        }
    }
}
