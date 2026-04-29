import Foundation

// MAG / Stalker Middleware HTTP client.
//
// Modern Stalker portals use a single load.php endpoint with type/action
// query parameters. Legacy portals (separate handshake.php, itv.php etc.)
// are also supported via automatic fallback.
//
// Auth flow (two-step):
//   1. load.php?type=stb&action=handshake&token=          → token1
//   2. load.php?type=stb&action=handshake&token=<token1>  → session token
public actor StalkerClient {

    public struct Config: Sendable {
        public let portalURL: String
        public let macAddress: String

        public init(portalURL: String, macAddress: String) {
            self.portalURL  = portalURL.trimmingCharacters(in: .init(charactersIn: "/"))
            self.macAddress = macAddress.uppercased()
        }

        // Derives /server base from whatever the user pasted.
        //   http://host/c              → http://host/server
        //   http://host/stalker_portal/c → http://host/stalker_portal/server
        //   http://host/stalker_portal → http://host/stalker_portal/server
        //   http://host/server         → unchanged
        //   http://host                → http://host/server
        fileprivate var serverBase: String {
            let p = portalURL
            if p.hasSuffix("/server")         { return p }
            if p.hasSuffix("/c")              { return String(p.dropLast(2)) + "/server" }
            if p.hasSuffix("/stalker_portal") { return p + "/server" }
            return p + "/server"
        }

        public var magUserAgent: String {
            let serial = macAddress.replacingOccurrences(of: ":", with: "")
            return "Mozilla/5.0 (QtEmbedded; U; Linux; C) AppleWebKit/533.3 (KHTML, like Gecko) " +
                   "MAG200 stbapp ver: 2.18.27 serial: \(serial) SDK/4.4.17 " +
                   "(Philips, magnet, Philips) SmartHub/4.2.0.0"
        }

        public var stalkerCookie: String {
            // Percent-encode the colons in the MAC address for strict RFC 6265
            // cookie-value compliance, matching the format the server expects
            // (e.g. mac=00%3A1A%3A79%3AF6%3A7E%3A02).
            let encodedMAC = macAddress
                .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? macAddress
            return "mac=\(encodedMAC); stb_lang=en; timezone=UTC"
        }
    }

    private let config: Config
    private let session: URLSession
    private var token: String?

    public init(config: Config, session: URLSession? = nil) {
        self.config  = config
        if let session {
            self.session = session
        } else {
            let cfg = URLSessionConfiguration.default
            cfg.timeoutIntervalForRequest = 30
            cfg.timeoutIntervalForResource = 120
            self.session = URLSession(configuration: cfg)
        }
    }

    // MARK: - Authentication

    /// Two-step handshake via load.php.
    public func authenticate() async throws {
        let base = config.serverBase

        // Step 1 — empty token → initial token
        let d1 = try await get("\(base)/load.php?type=stb&action=handshake&token=")
        guard let tok1 = parseToken(from: d1), !tok1.isEmpty else {
            throw StalkerError.tokenNotFound
        }

        // Step 2 — exchange initial token → session token
        let d2 = try await get(
            "\(base)/load.php?type=stb&action=handshake&token=\(tok1)",
            authToken: tok1
        )
        guard let tok2 = parseToken(from: d2), !tok2.isEmpty else {
            throw StalkerError.handshakeFailed
        }

        self.token = tok2
    }

    // MARK: - TV Genres

    public func tvGenres() async throws -> [Category] {
        let tok = try requireToken()
        let data = try await get(
            "\(config.serverBase)/load.php?type=itv&action=get_genres",
            authToken: tok
        )
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let js   = json["js"] as? [[String: Any]] else { return [] }
        return js.compactMap { dict in
            guard let id = stringOrInt(dict["id"]) else { return nil }
            let title = dict["title"] as? String ?? ""
            return Category(id: id, title: title)
        }
    }

    // MARK: - Channel list (paginated)

    public func channels() async throws -> [Channel] {
        let tok = try requireToken()

        // Fetch genre lookup so we can assign group names even if genre_title is missing
        let genres = (try? await tvGenres()) ?? []
        let genreMap = Dictionary(uniqueKeysWithValues: genres.map { ($0.id, $0.title) })

        var all: [Channel] = []
        var page = 1
        let pageSize = 500

        while true {
            let url = "\(config.serverBase)/load.php?type=itv&action=get_all_channels&p=\(page)&items_per_page=\(pageSize)"
            let data = try await get(url, authToken: tok)

            guard let json    = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let js      = json["js"] as? [String: Any],
                  let dataArr = js["data"] as? [[String: Any]] else { break }

            let totalItems = js["total_items"] as? Int ?? 0

            let batch = dataArr.compactMap { dict -> Channel? in
                guard let id   = stringOrInt(dict["id"]),
                      let name = dict["name"] as? String else { return nil }
                let raw   = dict["cmd"]         as? String ?? ""
                let cmd   = raw.hasPrefix("ffmpeg ") ? String(raw.dropFirst(7)) : raw
                let logo  = dict["logo"]        as? String

                // Use genre_title if available, otherwise look up by tv_genre_id
                var group = dict["genre_title"] as? String ?? ""
                if group.isEmpty, let gid = stringOrInt(dict["tv_genre_id"]) {
                    group = genreMap[gid] ?? ""
                }

                return Channel(id: id, name: name, groupTitle: group, logoURL: logo, streamURL: cmd)
            }

            all.append(contentsOf: batch)

            // Stop if we have all items (server returned everything at once),
            // or if we got a partial page (last page of a paginating server).
            if (totalItems > 0 && all.count >= totalItems) || batch.count < pageSize { break }
            page += 1
        }

        return all
    }

    // MARK: - VOD categories

    public struct Category: Sendable {
        public let id: String
        public let title: String
    }

    public func vodCategories() async throws -> [Category] {
        let tok  = try requireToken()
        let data = try await get(
            "\(config.serverBase)/load.php?type=vod&action=get_categories",
            authToken: tok
        )
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let js   = json["js"] as? [[String: Any]] else { return [] }
        return js.compactMap { dict in
            guard let id = stringOrInt(dict["id"]) else { return nil }
            let title = dict["title"] as? String ?? ""
            return Category(id: id, title: title)
        }
    }

    public func vodItems(categoryId: String) async throws -> [VODItem] {
        let tok  = try requireToken()
        let url  = "\(config.serverBase)/load.php?type=vod&action=get_ordered_list&category=\(categoryId)&p=1&items_per_page=500"
        let data = try await get(url, authToken: tok)

        guard let json    = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let js      = json["js"] as? [String: Any],
              let dataArr = js["data"] as? [[String: Any]] else { return [] }

        return dataArr.compactMap { dict -> VODItem? in
            guard let id   = stringOrInt(dict["id"]),
                  let name = dict["name"] as? String,
                  let cmd  = dict["cmd"] as? String else { return nil }
            return VODItem(
                id:        id,
                title:     name,
                posterURL: dict["screenshot_uri"] as? String,
                streamURL: cmd,
                type:      .movie
            )
        }
    }

    // MARK: - Series categories & items

    public func seriesCategories() async throws -> [Category] {
        let tok  = try requireToken()
        let data = try await get(
            "\(config.serverBase)/load.php?type=series&action=get_categories",
            authToken: tok
        )
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let js   = json["js"] as? [[String: Any]] else { return [] }
        return js.compactMap { dict in
            guard let id = stringOrInt(dict["id"]) else { return nil }
            let title = dict["title"] as? String ?? ""
            return Category(id: id, title: title)
        }
    }

    public func seriesItems(categoryId: String) async throws -> [Series] {
        let tok  = try requireToken()
        let url  = "\(config.serverBase)/load.php?type=series&action=get_ordered_list&category=\(categoryId)&p=1&items_per_page=500"
        let data = try await get(url, authToken: tok)

        guard let json    = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let js      = json["js"] as? [String: Any],
              let dataArr = js["data"] as? [[String: Any]] else { return [] }

        return dataArr.compactMap { dict -> Series? in
            guard let id   = stringOrInt(dict["id"]),
                  let name = dict["name"] as? String else { return nil }
            return Series(
                id:        id,
                title:     name,
                posterURL: dict["screenshot_uri"] as? String
            )
        }
    }

    // MARK: - Series detail (seasons & episodes)

    public func seriesSeasons(seriesId: String) async throws -> [Season] {
        let tok  = try requireToken()
        let data = try await get(
            "\(config.serverBase)/load.php?type=series&action=get_ordered_list&movie_id=\(seriesId)&season_id=0&episode_id=0",
            authToken: tok
        )
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let js   = json["js"] as? [String: Any] else { return [] }

        // Parse seasons list
        guard let seasonsArr = js["data"] as? [[String: Any]] else { return [] }

        var seasons: [Season] = []
        for seasonDict in seasonsArr {
            guard let seasonId   = stringOrInt(seasonDict["id"]),
                  let seasonNum  = seasonDict["season_number"] as? Int ?? Int(stringOrInt(seasonDict["id"]) ?? "") else { continue }

            // Fetch episodes for this season
            let epData = try await get(
                "\(config.serverBase)/load.php?type=series&action=get_ordered_list&movie_id=\(seriesId)&season_id=\(seasonId)&episode_id=0",
                authToken: tok
            )
            var episodes: [Episode] = []
            if let epJson = try? JSONSerialization.jsonObject(with: epData) as? [String: Any],
               let epJs   = epJson["js"] as? [String: Any],
               let epArr  = epJs["data"] as? [[String: Any]] {
                for (index, epDict) in epArr.enumerated() {
                    let epId   = stringOrInt(epDict["id"]) ?? UUID().uuidString
                    let epName = epDict["name"] as? String ?? "Episode \(index + 1)"
                    let cmd    = epDict["cmd"] as? String ?? ""
                    episodes.append(Episode(
                        id: epId,
                        episodeNumber: index + 1,
                        title: epName,
                        streamURL: cmd
                    ))
                }
            }

            seasons.append(Season(
                seasonNumber: seasonNum,
                episodes: episodes
            ))
        }
        return seasons.sorted { $0.seasonNumber < $1.seasonNumber }
    }

    // MARK: - Stream URL resolution

    /// Resolves a raw Stalker cmd to a final playable HTTP URL.
    ///
    /// This portal stores three distinct cmd formats:
    ///   1. Direct HTTP URL (live TV)  — already playable, return as-is.
    ///   2. Base64-encoded JSON (VOD)  — must call `type=vod&action=create_link`.
    ///   3. Other cmd string           — must call `type=itv&action=create_link`.
    public func resolveStreamURL(cmd: String) async throws -> String {
        let tok = try requireToken()

        // ── Case 1: Direct HTTP URL ───────────────────────────────────────────
        // Live-TV channels on this portal already embed a valid play_token in
        // the cmd URL. Calling create_link would overwrite the stream= parameter
        // with an empty value on this server. Use the raw URL directly.
        if cmd.hasPrefix("http://") || cmd.hasPrefix("https://") {
            return cmd
        }

        // ── Case 2 / 3: cmd needs server-side resolution ──────────────────────
        // Detect VOD by checking if cmd is base64-encoded JSON (no scheme, only
        // base64 alphabet characters) vs. a plain live-TV cmd string.
        let contentType = isBase64VODCmd(cmd) ? "vod" : "itv"

        let encoded = cmd.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? cmd

        // Try create_link; on auth failure, re-authenticate and retry once.
        let resolved = try await createLinkWithRetry(
            contentType: contentType, encoded: encoded, token: tok
        )
        return resolved
    }

    /// Calls create_link and retries once with a fresh token on auth failure.
    private func createLinkWithRetry(contentType: String, encoded: String, token: String) async throws -> String {
        let url = "\(config.serverBase)/load.php?type=\(contentType)&action=create_link&cmd=\(encoded)&series=0"

        let data = try await get(url, authToken: token)

        // Check for auth error (empty/missing js or token-expired indicator)
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let js = json["js"] as? [String: Any],
           let cmd2 = js["cmd"] as? String,
           !cmd2.isEmpty {
            return try validateResolvedCmd(cmd2)
        }

        // Possibly expired token — re-authenticate and retry once
        try await authenticate()
        let newTok = try requireToken()
        let retryData = try await get(url, authToken: newTok)

        guard let json = try? JSONSerialization.jsonObject(with: retryData) as? [String: Any],
              let js = json["js"] as? [String: Any],
              let cmd2 = js["cmd"] as? String,
              !cmd2.isEmpty else {
            throw StalkerError.streamResolutionFailed
        }
        return try validateResolvedCmd(cmd2)
    }

    /// Strips ffmpeg prefix and validates the resolved URL doesn't have empty stream= param.
    private func validateResolvedCmd(_ cmd2: String) throws -> String {
        let resolved = cmd2.hasPrefix("ffmpeg ") ? String(cmd2.dropFirst(7)) : cmd2

        // Guard against portals that return a broken URL with an empty stream= param.
        guard !resolved.contains("stream=&"),
              !resolved.hasSuffix("stream="),
              !resolved.hasSuffix("stream=\n") else {
            throw StalkerError.streamResolutionFailed
        }
        return resolved
    }

    /// Returns true when `cmd` looks like a base64-encoded VOD payload rather
    /// than a URL or a plain live-TV cmd string.
    private func isBase64VODCmd(_ cmd: String) -> Bool {
        guard !cmd.hasPrefix("http"), !cmd.contains("://") else { return false }
        let b64 = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=-_")
        return cmd.unicodeScalars.allSatisfy { b64.contains($0) }
    }

    // MARK: - Networking

    private func get(_ urlString: String,
                     authToken: String? = nil) async throws -> Data {
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue(config.magUserAgent,   forHTTPHeaderField: "User-Agent")
        request.setValue(config.stalkerCookie,  forHTTPHeaderField: "Cookie")
        request.setValue("\(config.serverBase)/", forHTTPHeaderField: "Referer")
        if let tok = authToken {
            request.setValue("Bearer \(tok)", forHTTPHeaderField: "Authorization")
        }
        let (data, _) = try await session.data(for: request)
        return data
    }

    // MARK: - Helpers

    private func parseToken(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let js   = json["js"] as? [String: Any] else { return nil }
        return js["token"] as? String
    }

    private func stringOrInt(_ value: Any?) -> String? {
        if let s = value as? String { return s }
        if let i = value as? Int    { return "\(i)" }
        return nil
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
        case .notAuthenticated:
            return "Not authenticated — call authenticate() first"
        case .tokenNotFound:
            return "Could not retrieve session token — check portal URL and MAC address"
        case .handshakeFailed:
            return "Handshake failed — check portal URL and MAC address"
        case .streamResolutionFailed:
            return "Could not resolve stream URL"
        }
    }
}
