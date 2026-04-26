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
