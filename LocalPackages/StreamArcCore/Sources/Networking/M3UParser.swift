import Foundation

// Parses M3U/M3U8 playlists into typed Channel and VODItem arrays.
// Heuristic: groups containing "movie", "vod", "film", "series", or "show" in
// their group-title are treated as VOD; everything else is Live TV.
public struct M3UParser {

    public struct ParseResult: Sendable {
        public var channels: [Channel]
        public var vodItems: [VODItem]

        public init(channels: [Channel] = [], vodItems: [VODItem] = []) {
            self.channels = channels
            self.vodItems = vodItems
        }
    }

    public enum M3UError: Error, LocalizedError {
        case httpError(statusCode: Int)
        case emptyResponse
        case notM3U
        case xtreamDetected(baseURL: String, username: String, password: String)

        public var errorDescription: String? {
            switch self {
            case .httpError(let code):
                return "Server returned HTTP \(code) — the URL may be invalid or credentials expired"
            case .emptyResponse:
                return "Server returned an empty response — check the URL and credentials"
            case .notM3U:
                return "Response is not a valid M3U playlist — check the URL format"
            case .xtreamDetected:
                return "This is an Xtream Codes URL — use the Xtream source type instead"
            }
        }
    }

    /// Extracts Xtream Codes credentials from M3U-style URLs.
    /// e.g. http://host:port/get.php?username=X&password=Y&type=m3u_plus → (baseURL, user, pass)
    public struct XtreamCredentials: Sendable {
        public let baseURL: String
        public let username: String
        public let password: String
    }

    public static func extractXtreamCredentials(from urlString: String) -> XtreamCredentials? {
        guard let url = URL(string: urlString),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = components.queryItems else { return nil }

        let username = items.first(where: { $0.name == "username" })?.value
        let password = items.first(where: { $0.name == "password" })?.value

        guard let username, !username.isEmpty,
              let password, !password.isEmpty else { return nil }

        // Build base URL: scheme + host + port
        var base = "\(url.scheme ?? "http")://\(url.host ?? "")"
        if let port = url.port, port != 80 && port != 443 {
            base += ":\(port)"
        }

        return XtreamCredentials(baseURL: base, username: username, password: password)
    }

    private static let vodKeywords: Set<String> = ["movie", "vod", "film", "series", "show", "episode", "films"]

    // MARK: - Public API

    public static func parse(content: String) -> ParseResult {
        var result = ParseResult()

        // Strip BOM if present
        var cleaned = content
        if cleaned.hasPrefix("\u{FEFF}") {
            cleaned = String(cleaned.dropFirst())
        }

        let lines = cleaned.components(separatedBy: .newlines)

        guard lines.first?.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("#EXTM3U") == true else {
            return result
        }

        // ...existing parsing logic...
        var idx = 1
        while idx < lines.count {
            let line = lines[idx].trimmingCharacters(in: .whitespacesAndNewlines)

            if line.hasPrefix("#EXTINF:") {
                let (url, headers, nextIdx) = nextStreamURL(in: lines, from: idx + 1)
                if let streamURL = url {
                    let attrs = extractAttributes(from: line)
                    let title = extractTitle(from: line, attrs: attrs)
                    let group = attrs["group-title"] ?? ""

                    if isVOD(group: group) {
                        let type: VODType = group.lowercased().contains("series") ||
                                           group.lowercased().contains("show") ? .series : .movie
                        var item = VODItem(
                            title: title,
                            posterURL: attrs["tvg-logo"],
                            streamURL: streamURL,
                            type: type,
                            groupTitle: group
                        )
                        item.httpHeaders = headers
                        result.vodItems.append(item)
                    } else {
                        result.channels.append(Channel(
                            name: title,
                            groupTitle: group,
                            logoURL: attrs["tvg-logo"],
                            streamURL: streamURL,
                            epgId: attrs["tvg-id"],
                            httpHeaders: headers
                        ))
                    }
                    idx = nextIdx
                } else {
                    idx += 1
                }
            } else {
                idx += 1
            }
        }

        // Deduplicate channels with the same tvg-id: keep first as primary, collect rest as fallbacks
        result.channels = Self.deduplicateChannels(result.channels)
        return result
    }

    /// Groups channels sharing the same non-empty tvg-id. The first occurrence keeps its
    /// streamURL as primary; subsequent duplicates are appended to fallbackURLs.
    private static func deduplicateChannels(_ channels: [Channel]) -> [Channel] {
        var seen: [String: Int] = [:]       // tvg-id → index in output
        var output: [Channel] = []
        for ch in channels {
            guard let epgId = ch.epgId, !epgId.isEmpty else {
                output.append(ch)
                continue
            }
            if let existingIdx = seen[epgId] {
                output[existingIdx].fallbackURLs.append(ch.streamURL)
            } else {
                seen[epgId] = output.count
                output.append(ch)
            }
        }
        return output
    }

    public static func parse(url: URL) async throws -> ParseResult {
        let content: String
        if url.isFileURL {
            content = try String(contentsOf: url, encoding: .utf8)
        } else {
            var request = URLRequest(url: url, timeoutInterval: 30)
            // Some IPTV providers block default User-Agent
            request.setValue(
                "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
                forHTTPHeaderField: "User-Agent"
            )

            let cfg = URLSessionConfiguration.default
            cfg.timeoutIntervalForRequest = 30
            cfg.timeoutIntervalForResource = 300   // large playlists
            let session = URLSession(configuration: cfg)

            let (data, response) = try await session.data(for: request)

            // Check HTTP status
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                // If this looks like an Xtream URL, try the Xtream API as fallback
                if let creds = extractXtreamCredentials(from: url.absoluteString) {
                    return try await fallbackToXtream(creds: creds)
                }
                throw M3UError.httpError(statusCode: http.statusCode)
            }

            guard !data.isEmpty else {
                // If this looks like an Xtream URL, try the Xtream API as fallback
                if let creds = extractXtreamCredentials(from: url.absoluteString) {
                    return try await fallbackToXtream(creds: creds)
                }
                throw M3UError.emptyResponse
            }

            // Try UTF-8 first, fall back to Latin-1
            if let str = String(data: data, encoding: .utf8) {
                content = str
            } else if let str = String(data: data, encoding: .isoLatin1) {
                content = str
            } else {
                content = String(decoding: data, as: UTF8.self)
            }
        }

        let result = parse(content: content)

        // If parsing returned nothing but we got data, the format may be wrong
        if result.channels.isEmpty && result.vodItems.isEmpty && !content.isEmpty {
            // Check if it looked like an M3U at all
            let trimmed = content.replacingOccurrences(of: "\u{FEFF}", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.hasPrefix("#EXTM3U") {
                // Try Xtream fallback before giving up
                if let creds = extractXtreamCredentials(from: url.absoluteString) {
                    return try await fallbackToXtream(creds: creds)
                }
                throw M3UError.notM3U
            }
        }

        return result
    }

    /// Falls back to using the Xtream Codes API when the M3U endpoint is blocked.
    private static func fallbackToXtream(creds: XtreamCredentials) async throws -> ParseResult {
        let client = XtreamClient(config: .init(
            baseURL: creds.baseURL,
            username: creds.username,
            password: creds.password
        ))
        async let channels = client.asChannels()
        async let vodItems = client.asVODItems()
        return ParseResult(
            channels: (try? await channels) ?? [],
            vodItems: (try? await vodItems) ?? []
        )
    }

    // MARK: - Private helpers

    /// Returns (cleanURL, httpHeaders, nextLineIndex).
    /// Collects #EXTVLCOPT option lines and pipe-suffix headers from the URL line.
    private static func nextStreamURL(in lines: [String], from start: Int) -> (url: String?, headers: [String: String], nextIdx: Int) {
        var i = start
        var headers: [String: String] = [:]
        while i < lines.count {
            let l = lines[i].trimmingCharacters(in: .whitespacesAndNewlines)
            if l.isEmpty || l.hasPrefix("#EXTINF") { break }
            if l.hasPrefix("#EXTVLCOPT:") {
                parseEXTVLCOPT(l, into: &headers)
            } else if !l.hasPrefix("#") {
                var urlStr = l
                if let pipeIdx = l.firstIndex(of: "|") {
                    urlStr = String(l[l.startIndex..<pipeIdx])
                    parsePipeSuffix(String(l[l.index(after: pipeIdx)...]), into: &headers)
                }
                return (urlStr.isEmpty ? nil : urlStr, headers, i + 1)
            }
            i += 1
        }
        return (nil, headers, i)
    }

    private static func parseEXTVLCOPT(_ line: String, into headers: inout [String: String]) {
        let opt = String(line.dropFirst("#EXTVLCOPT:".count))
        guard let eqIdx = opt.firstIndex(of: "=") else { return }
        let key = String(opt[opt.startIndex..<eqIdx]).lowercased().trimmingCharacters(in: .whitespaces)
        let value = String(opt[opt.index(after: eqIdx)...]).trimmingCharacters(in: .whitespaces)
        switch key {
        case "http-user-agent": headers["User-Agent"] = value
        case "http-referrer":   headers["Referer"] = value
        case "http-origin":     headers["Origin"] = value
        default: break
        }
    }

    private static func parsePipeSuffix(_ suffix: String, into headers: inout [String: String]) {
        for part in suffix.components(separatedBy: "&") {
            guard let eqIdx = part.firstIndex(of: "=") else { continue }
            let key = String(part[part.startIndex..<eqIdx]).trimmingCharacters(in: .whitespaces)
            let value = String(part[part.index(after: eqIdx)...]).trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }
            switch key.lowercased() {
            case "user-agent": headers["User-Agent"] = value
            case "referer":    headers["Referer"] = value
            case "origin":     headers["Origin"] = value
            default:           headers[key] = value
            }
        }
    }

    // ...existing extractAttributes, extractTitle, isVOD unchanged...
    private static func extractAttributes(from extinf: String) -> [String: String] {
        var result: [String: String] = [:]
        let pattern = #"([\w-]+)="([^"]*)""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return result }
        let range = NSRange(extinf.startIndex..., in: extinf)
        for match in regex.matches(in: extinf, range: range) {
            if let k = Range(match.range(at: 1), in: extinf),
               let v = Range(match.range(at: 2), in: extinf) {
                result[String(extinf[k])] = String(extinf[v])
            }
        }
        return result
    }

    private static func extractTitle(from extinf: String, attrs: [String: String]) -> String {
        if let name = attrs["tvg-name"], !name.isEmpty { return name }
        if let comma = extinf.lastIndex(of: ",") {
            let after = String(extinf[extinf.index(after: comma)...]).trimmingCharacters(in: .whitespaces)
            if !after.isEmpty { return after }
        }
        return "Unknown"
    }

    private static func isVOD(group: String) -> Bool {
        let lower = group.lowercased()
        return vodKeywords.contains(where: { lower.contains($0) })
    }
}
