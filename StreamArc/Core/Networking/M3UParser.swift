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

    private static let vodKeywords: Set<String> = ["movie", "vod", "film", "series", "show", "episode", "films"]

    // MARK: - Public API

    public static func parse(content: String) -> ParseResult {
        var result = ParseResult()
        let lines = content.components(separatedBy: .newlines)

        guard lines.first?.trimmingCharacters(in: .whitespaces).hasPrefix("#EXTM3U") == true else {
            return result
        }

        var idx = 1
        while idx < lines.count {
            let line = lines[idx].trimmingCharacters(in: .whitespaces)

            if line.hasPrefix("#EXTINF:") {
                let (url, nextIdx) = nextStreamURL(in: lines, from: idx + 1)
                if let streamURL = url {
                    let attrs = extractAttributes(from: line)
                    let title = extractTitle(from: line, attrs: attrs)
                    let group = attrs["group-title"] ?? ""

                    if isVOD(group: group) {
                        let type: VODType = group.lowercased().contains("series") ||
                                           group.lowercased().contains("show") ? .series : .movie
                        result.vodItems.append(VODItem(
                            title: title,
                            posterURL: attrs["tvg-logo"],
                            streamURL: streamURL,
                            type: type,
                            groupTitle: group
                        ))
                    } else {
                        result.channels.append(Channel(
                            name: title,
                            groupTitle: group,
                            logoURL: attrs["tvg-logo"],
                            streamURL: streamURL,
                            epgId: attrs["tvg-id"]
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

        return result
    }

    public static func parse(url: URL) async throws -> ParseResult {
        let content: String
        if url.isFileURL {
            content = try String(contentsOf: url, encoding: .utf8)
        } else {
            let (data, _) = try await URLSession.shared.data(from: url)
            content = String(decoding: data, as: UTF8.self)
        }
        return parse(content: content)
    }

    // MARK: - Private helpers

    private static func nextStreamURL(in lines: [String], from start: Int) -> (String?, Int) {
        var i = start
        while i < lines.count {
            let l = lines[i].trimmingCharacters(in: .whitespaces)
            if l.isEmpty || l.hasPrefix("#EXTINF") {
                break
            }
            if !l.hasPrefix("#") {
                return (l, i + 1)
            }
            i += 1
        }
        return (nil, i)
    }

    private static func extractAttributes(from extinf: String) -> [String: String] {
        var result: [String: String] = [:]
        // Matches:  key="value"
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
