import Foundation

// Xtream Codes API client — username/password authentication.
// All network calls use URLSession with async/await.
public actor XtreamClient {

    public struct Config: Sendable {
        public let baseURL: String
        public let username: String
        public let password: String

        public init(baseURL: String, username: String, password: String) {
            self.baseURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            self.username = username
            self.password = password
        }

        fileprivate var apiBase: String {
            "\(baseURL)/player_api.php?username=\(username)&password=\(password)"
        }
    }

    private let config: Config
    private let session: URLSession

    public init(config: Config, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    // MARK: - Live TV

    public func liveCategories() async throws -> [XtreamCategory] {
        try await fetch(action: "get_live_categories")
    }

    public func liveStreams(categoryId: String? = nil) async throws -> [XtreamStream] {
        var url = "\(config.apiBase)&action=get_live_streams"
        if let id = categoryId { url += "&category_id=\(id)" }
        return try await decode(from: url)
    }

    // MARK: - VOD

    public func vodCategories() async throws -> [XtreamCategory] {
        try await fetch(action: "get_vod_categories")
    }

    public func vodStreams(categoryId: String? = nil) async throws -> [XtreamStream] {
        var url = "\(config.apiBase)&action=get_vod_streams"
        if let id = categoryId { url += "&category_id=\(id)" }
        return try await decode(from: url)
    }

    // MARK: - Series

    public func seriesCategories() async throws -> [XtreamCategory] {
        try await fetch(action: "get_series_categories")
    }

    public func series(categoryId: String? = nil) async throws -> [XtreamSeriesInfo] {
        var url = "\(config.apiBase)&action=get_series"
        if let id = categoryId { url += "&category_id=\(id)" }
        return try await decode(from: url)
    }

    public func seriesDetail(seriesId: String) async throws -> XtreamSeriesDetail {
        let url = "\(config.apiBase)&action=get_series_info&series_id=\(seriesId)"
        return try await decode(from: url)
    }

    // MARK: - Convenience converters

    public func asChannels(categoryId: String? = nil) async throws -> [Channel] {
        let streams = try await liveStreams(categoryId: categoryId)
        return streams.map { s in
            Channel(
                id: "\(s.streamId)",
                name: s.name,
                groupTitle: s.categoryId ?? "",
                logoURL: s.streamIcon,
                streamURL: buildLiveURL(streamId: s.streamId, ext: s.containerExtension ?? "ts"),
                epgId: s.epgChannelId
            )
        }
    }

    public func asVODItems(categoryId: String? = nil) async throws -> [VODItem] {
        let streams = try await vodStreams(categoryId: categoryId)
        return streams.map { s in
            VODItem(
                id: "\(s.streamId)",
                title: s.name,
                posterURL: s.streamIcon,
                streamURL: buildVODURL(streamId: s.streamId, ext: s.containerExtension ?? "mp4"),
                type: .movie,
                groupTitle: s.categoryId ?? ""
            )
        }
    }

    public func asSeries(categoryId: String? = nil) async throws -> [Series] {
        let list = try await series(categoryId: categoryId)
        return list.map { s in
            Series(
                id: "\(s.seriesId)",
                title: s.name,
                posterURL: s.cover
            )
        }
    }

    /// Fetch full series detail and return seasons with episodes
    public func asSeriesSeasons(seriesId: String) async throws -> [Season] {
        let detail = try await seriesDetail(seriesId: seriesId)
        var seasonMap: [Int: [Episode]] = [:]

        for (_, episodes) in detail.allEpisodes {
            for ep in episodes {
                let streamURL = "\(config.baseURL)/series/\(config.username)/\(config.password)/\(ep.id).\(ep.containerExtension)"
                let episode = Episode(
                    id: ep.id,
                    episodeNumber: ep.episodeNum,
                    title: ep.title,
                    streamURL: streamURL
                )
                seasonMap[ep.season, default: []].append(episode)
            }
        }

        return seasonMap.keys.sorted().map { seasonNum in
            Season(
                seasonNumber: seasonNum,
                episodes: seasonMap[seasonNum]!.sorted { $0.episodeNumber < $1.episodeNumber }
            )
        }
    }

    // MARK: - URL builders

    private func buildLiveURL(streamId: Int, ext: String) -> String {
        "\(config.baseURL)/live/\(config.username)/\(config.password)/\(streamId).\(ext)"
    }

    private func buildVODURL(streamId: Int, ext: String) -> String {
        "\(config.baseURL)/movie/\(config.username)/\(config.password)/\(streamId).\(ext)"
    }

    // MARK: - Networking

    private func fetch<T: Decodable>(action: String) async throws -> T {
        let urlStr = "\(config.apiBase)&action=\(action)"
        return try await decode(from: urlStr)
    }

    private func decode<T: Decodable>(from urlString: String) async throws -> T {
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        let (data, _) = try await session.data(from: url)
        return try JSONDecoder().decode(T.self, from: data)
    }
}

// MARK: - Xtream API types

public struct XtreamCategory: Decodable, Sendable {
    public let categoryId: String
    public let categoryName: String

    enum CodingKeys: String, CodingKey {
        case categoryId = "category_id"
        case categoryName = "category_name"
    }
}

public struct XtreamStream: Decodable, Sendable {
    public let streamId: Int
    public let name: String
    public let streamIcon: String?
    public let categoryId: String?
    public let epgChannelId: String?
    public let containerExtension: String?

    enum CodingKeys: String, CodingKey {
        case streamId = "stream_id"
        case name
        case streamIcon = "stream_icon"
        case categoryId = "category_id"
        case epgChannelId = "epg_channel_id"
        case containerExtension = "container_extension"
    }
}

public struct XtreamSeriesInfo: Decodable, Sendable {
    public let seriesId: Int
    public let name: String
    public let cover: String?
    public let categoryId: String?

    enum CodingKeys: String, CodingKey {
        case seriesId = "series_id"
        case name
        case cover
        case categoryId = "category_id"
    }
}

public struct XtreamSeriesDetail: Decodable, Sendable {
    public let info: XtreamSeriesMetadata
    public let seasons: [String: [XtreamEpisode]]?
    public let episodes: [String: [XtreamEpisode]]?

    var allEpisodes: [String: [XtreamEpisode]] { episodes ?? seasons ?? [:] }
}

public struct XtreamSeriesMetadata: Decodable, Sendable {
    public let name: String?
    public let cover: String?
    public let plot: String?
    public let rating: String?
}

public struct XtreamEpisode: Decodable, Sendable {
    public let id: String
    public let title: String
    public let season: Int
    public let episodeNum: Int
    public let containerExtension: String

    enum CodingKeys: String, CodingKey {
        case id, title, season
        case episodeNum = "episode_num"
        case containerExtension = "container_extension"
    }
}
