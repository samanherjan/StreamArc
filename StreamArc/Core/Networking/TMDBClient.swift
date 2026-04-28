import Foundation

// TMDB API v3 client for metadata and trailer lookups.
// API key is stored in UserDefaults via SettingsStore and passed in per-request.
// Results are cached in memory to avoid redundant API calls.
public actor TMDBClient {

    public static let shared = TMDBClient()

    private let baseURL = "https://api.themoviedb.org/3"
    private let session: URLSession
    private var videoCache: [Int: [TMDBVideo]] = [:]
    private var searchCache: [String: Int] = [:]    // "title_year" → tmdbId
    private var detailCache: [Int: TMDBDetail] = [:]

    public init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Search

    public func searchMovie(title: String, year: Int? = nil, apiKey: String) async throws -> Int? {
        let cacheKey = "\(title)_\(year ?? 0)_movie"
        if let cached = searchCache[cacheKey] { return cached }

        var components = URLComponents(string: "\(baseURL)/search/movie")!
        components.queryItems = [
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "query", value: title),
            year.map { URLQueryItem(name: "year", value: "\($0)") }
        ].compactMap { $0 }

        let results: TMDBSearchResponse = try await decode(from: components.url!)
        if let first = results.results.first {
            searchCache[cacheKey] = first.id
            return first.id
        }
        return nil
    }

    public func searchTV(title: String, apiKey: String) async throws -> Int? {
        let cacheKey = "\(title)_tv"
        if let cached = searchCache[cacheKey] { return cached }

        var components = URLComponents(string: "\(baseURL)/search/tv")!
        components.queryItems = [
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "query", value: title)
        ]

        let results: TMDBSearchResponse = try await decode(from: components.url!)
        if let first = results.results.first {
            searchCache[cacheKey] = first.id
            return first.id
        }
        return nil
    }

    // MARK: - Videos (trailers)

    public func videos(tmdbId: Int, mediaType: TMDBMediaType, apiKey: String) async throws -> [TMDBVideo] {
        if let cached = videoCache[tmdbId] { return cached }

        let url = URL(string: "\(baseURL)/\(mediaType.rawValue)/\(tmdbId)/videos?api_key=\(apiKey)")!
        let response: TMDBVideoResponse = try await decode(from: url)
        let trailers = response.results.filter { $0.type == "Trailer" && $0.site == "YouTube" }
        videoCache[tmdbId] = trailers
        return trailers
    }

    /// Convenience: returns the first YouTube trailer URL for the given item.
    public func trailerURL(for item: VODItem, apiKey: String) async -> URL? {
        guard !apiKey.isEmpty else { return nil }
        do {
            let mediaType: TMDBMediaType = item.type == .series ? .tv : .movie
            let id: Int?
            if let existing = item.tmdbId {
                id = existing
            } else {
                id = item.type == .series
                    ? try await searchTV(title: item.title, apiKey: apiKey)
                    : try await searchMovie(title: item.title, year: item.year, apiKey: apiKey)
            }
            guard let tmdbId = id else { return nil }
            let videos = try await videos(tmdbId: tmdbId, mediaType: mediaType, apiKey: apiKey)
            return videos.first.flatMap { URL(string: "https://www.youtube.com/watch?v=\($0.key)") }
        } catch {
            return nil
        }
    }

    // MARK: - Details

    public func movieDetail(tmdbId: Int, apiKey: String) async throws -> TMDBDetail {
        if let cached = detailCache[tmdbId] { return cached }
        let url = URL(string: "\(baseURL)/movie/\(tmdbId)?api_key=\(apiKey)")!
        let detail: TMDBDetail = try await decode(from: url)
        detailCache[tmdbId] = detail
        return detail
    }

    public func tvDetail(tmdbId: Int, apiKey: String) async throws -> TMDBDetail {
        if let cached = detailCache[tmdbId] { return cached }
        let url = URL(string: "\(baseURL)/tv/\(tmdbId)?api_key=\(apiKey)")!
        let detail: TMDBDetail = try await decode(from: url)
        detailCache[tmdbId] = detail
        return detail
    }

    /// Convenience: fetch detail for a VODItem (searches if needed)
    public func fetchDetail(for item: VODItem, apiKey: String) async -> TMDBDetail? {
        guard !apiKey.isEmpty else { return nil }
        do {
            let mediaType: TMDBMediaType = item.type == .series ? .tv : .movie
            let id: Int?
            if let existing = item.tmdbId {
                id = existing
            } else {
                id = item.type == .series
                    ? try await searchTV(title: item.title, apiKey: apiKey)
                    : try await searchMovie(title: item.title, year: item.year, apiKey: apiKey)
            }
            guard let tmdbId = id else { return nil }
            return mediaType == .tv
                ? try await tvDetail(tmdbId: tmdbId, apiKey: apiKey)
                : try await movieDetail(tmdbId: tmdbId, apiKey: apiKey)
        } catch {
            return nil
        }
    }

    /// Convenience: fetch detail for a Series
    public func fetchDetail(forSeries series: Series, apiKey: String) async -> TMDBDetail? {
        guard !apiKey.isEmpty else { return nil }
        do {
            let id: Int?
            if let existing = series.tmdbId {
                id = existing
            } else {
                id = try await searchTV(title: series.title, apiKey: apiKey)
            }
            guard let tmdbId = id else { return nil }
            return try await tvDetail(tmdbId: tmdbId, apiKey: apiKey)
        } catch {
            return nil
        }
    }

    // MARK: - Networking

    private func decode<T: Decodable>(from url: URL) async throws -> T {
        let (data, _) = try await session.data(from: url)
        return try JSONDecoder().decode(T.self, from: data)
    }
}

// MARK: - TMDB types

public enum TMDBMediaType: String, Sendable {
    case movie, tv
}

public struct TMDBSearchResponse: Decodable {
    let results: [TMDBSearchResult]
}

public struct TMDBSearchResult: Decodable {
    let id: Int
}

public struct TMDBVideoResponse: Decodable {
    let results: [TMDBVideo]
}

public struct TMDBVideo: Decodable, Sendable {
    public let key: String
    public let site: String
    public let type: String
    public let name: String
}

public struct TMDBDetail: Decodable, Sendable {
    public let id: Int
    public let overview: String?
    public let voteAverage: Double?
    public let releaseDate: String?      // movie
    public let firstAirDate: String?     // tv
    public let genres: [TMDBGenre]?
    public let runtime: Int?             // movie
    public let numberOfSeasons: Int?     // tv
    public let tagline: String?
    public let status: String?

    enum CodingKeys: String, CodingKey {
        case id, overview, genres, runtime, tagline, status
        case voteAverage = "vote_average"
        case releaseDate = "release_date"
        case firstAirDate = "first_air_date"
        case numberOfSeasons = "number_of_seasons"
    }

    public var yearString: String? {
        let date = releaseDate ?? firstAirDate
        guard let date, date.count >= 4 else { return nil }
        return String(date.prefix(4))
    }
}

public struct TMDBGenre: Decodable, Sendable {
    public let id: Int
    public let name: String
}
