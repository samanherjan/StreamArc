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
    private var castCache: [Int: [TMDBCastMember]] = [:]
    private var similarCache: [Int: [TMDBSimilarItem]] = [:]
    private var ratingCache: [Int: String] = [:]
    private var trendingMoviesCache: (date: Date, items: [TMDBTrendingItem])?
    private var trendingTVCache: (date: Date, items: [TMDBTrendingItem])?
    private static let trendingCacheTTL: TimeInterval = 3600 // 1 hour

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

    /// Returns the YouTube video key for the first trailer of the given item.
    public func youtubeTrailerKey(for item: VODItem, apiKey: String) async -> String? {
        guard !apiKey.isEmpty else { return nil }
        do {
            let mediaType: TMDBMediaType = item.type == .series ? .tv : .movie
            let cleanTitle = Self.sanitizeTitle(item.title)
            let id: Int?
            if let existing = item.tmdbId {
                id = existing
            } else {
                id = item.type == .series
                    ? try await searchTV(title: cleanTitle, apiKey: apiKey)
                    : try await searchMovie(title: cleanTitle, year: item.year, apiKey: apiKey)
            }
            // If year-specific search fails, retry without year
            var tmdbId = id
            if tmdbId == nil, item.year != nil, item.type != .series {
                tmdbId = try await searchMovie(title: cleanTitle, year: nil, apiKey: apiKey)
            }
            guard let finalId = tmdbId else { return nil }
            let vids = try await videos(tmdbId: finalId, mediaType: mediaType, apiKey: apiKey)
            return vids.first?.key
        } catch {
            return nil
        }
    }

    /// Returns the IMDb ID for a movie via TMDB detail lookup.
    public func imdbId(for item: VODItem, apiKey: String) async -> String? {
        guard !apiKey.isEmpty else { return nil }
        do {
            let cleanTitle = Self.sanitizeTitle(item.title)
            let id: Int?
            if let existing = item.tmdbId {
                id = existing
            } else {
                id = item.type == .series
                    ? try await searchTV(title: cleanTitle, apiKey: apiKey)
                    : try await searchMovie(title: cleanTitle, year: item.year, apiKey: apiKey)
            }
            guard let tmdbId = id else { return nil }
            let detail = item.type == .series
                ? try await tvDetail(tmdbId: tmdbId, apiKey: apiKey)
                : try await movieDetail(tmdbId: tmdbId, apiKey: apiKey)
            return detail.imdbId
        } catch {
            return nil
        }
    }

    /// Returns the IMDb ID directly from a known TMDB ID (no VODItem needed).
    public func imdbIdDirect(tmdbId: Int, mediaType: TMDBMediaType, apiKey: String) async throws -> String? {
        let detail = mediaType == .tv
            ? try await tvDetail(tmdbId: tmdbId, apiKey: apiKey)
            : try await movieDetail(tmdbId: tmdbId, apiKey: apiKey)
        return detail.imdbId
    }

    // MARK: - Title Sanitization

    /// Cleans IPTV portal titles for TMDB search.
    private static func sanitizeTitle(_ raw: String) -> String {
        var title = raw
        // Remove file extensions
        for ext in [".mkv", ".avi", ".mp4", ".ts", ".m4v"] {
            if title.lowercased().hasSuffix(ext) {
                title = String(title.dropLast(ext.count))
            }
        }
        // Remove generic portal prefixes: any combo of word chars / dots / digits
        // followed by a dash separator, e.g. "4K.AMZ-", "FHD.NF-", "TOP-", "VOD:"
        // Must appear at the very start of the string.
        title = title.replacingOccurrences(
            of: #"^[\w.]+\s*[-:|]\s*"#,
            with: "", options: [.regularExpression, .caseInsensitive])
        // Remove [bracketed] content
        title = title.replacingOccurrences(of: #"\[.*?\]"#, with: "", options: .regularExpression)
        // Remove trailing country code in parens: (US), (UK), (FR), (DE), …
        title = title.replacingOccurrences(
            of: #"\s*\([A-Z]{2,3}\)\s*$"#, with: "", options: .regularExpression)
        // Remove (year) parentheticals
        title = title.replacingOccurrences(
            of: #"\(\d{4}\)"#, with: "", options: .regularExpression)
        // Remove (quality/format) parentheticals
        title = title.replacingOccurrences(
            of: #"\((?:HD|SD|4K|\d+p|CAM|TS|WEB|BluRay|Multi).*?\)"#,
            with: "", options: [.regularExpression, .caseInsensitive])
        // Remove quality/codec tags standing alone as words
        title = title.replacingOccurrences(
            of: #"\b(720p|1080p|2160p|4K|UHD|HD|SD|WEB-?DL|WEBRip|BluRay|BRRip|DVDRip|HDTV|x264|x265|HEVC|AAC|DTS|10bit|HDR)\b"#,
            with: "", options: [.regularExpression, .caseInsensitive])
        // Remove trailing year
        title = title.replacingOccurrences(of: #"\s*\d{4}\s*$"#, with: "", options: .regularExpression)
        // Dots/underscores to spaces
        title = title.replacingOccurrences(of: ".", with: " ")
        title = title.replacingOccurrences(of: "_", with: " ")
        // Collapse whitespace
        title = title.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        return title.trimmingCharacters(in: .whitespacesAndNewlines)
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

    // MARK: - Cast & Crew

    public func cast(tmdbId: Int, mediaType: TMDBMediaType, apiKey: String) async throws -> [TMDBCastMember] {
        if let cached = castCache[tmdbId] { return cached }
        let url = URL(string: "\(baseURL)/\(mediaType.rawValue)/\(tmdbId)/credits?api_key=\(apiKey)")!
        let response: TMDBCreditsResponse = try await decode(from: url)
        let members = Array(response.cast.prefix(15))
        castCache[tmdbId] = members
        return members
    }

    // MARK: - Similar

    public func similar(tmdbId: Int, mediaType: TMDBMediaType, apiKey: String) async throws -> [TMDBSimilarItem] {
        if let cached = similarCache[tmdbId] { return cached }
        let url = URL(string: "\(baseURL)/\(mediaType.rawValue)/\(tmdbId)/similar?api_key=\(apiKey)")!
        let response: TMDBSimilarResponse = try await decode(from: url)
        let items = Array(response.results.prefix(20))
        similarCache[tmdbId] = items
        return items
    }

    // MARK: - Content Rating

    /// Returns the US content rating (e.g. "PG-13", "TV-MA") for the item.
    public func contentRating(tmdbId: Int, mediaType: TMDBMediaType, apiKey: String) async throws -> String? {
        if let cached = ratingCache[tmdbId] { return cached }
        let rating: String?
        if mediaType == .movie {
            let url = URL(string: "\(baseURL)/movie/\(tmdbId)/release_dates?api_key=\(apiKey)")!
            let response: TMDBReleaseDatesResponse = try await decode(from: url)
            rating = response.results
                .first { $0.iso31661 == "US" }?
                .releaseDates
                .first { !$0.certification.isEmpty }?
                .certification
        } else {
            let url = URL(string: "\(baseURL)/tv/\(tmdbId)/content_ratings?api_key=\(apiKey)")!
            let response: TMDBContentRatingsResponse = try await decode(from: url)
            rating = response.results.first { $0.iso31661 == "US" }?.rating
        }
        if let rating { ratingCache[tmdbId] = rating }
        return rating
    }

    // MARK: - Trending

    public func trendingMovies(timeWindow: String = "week", apiKey: String) async throws -> [TMDBTrendingItem] {
        let now = Date()
        if let cache = trendingMoviesCache, now.timeIntervalSince(cache.date) < Self.trendingCacheTTL {
            return cache.items
        }
        let url = URL(string: "\(baseURL)/trending/movie/\(timeWindow)?api_key=\(apiKey)")!
        let response: TMDBTrendingResponse = try await decode(from: url)
        trendingMoviesCache = (date: now, items: response.results)
        return response.results
    }

    public func trendingTV(timeWindow: String = "week", apiKey: String) async throws -> [TMDBTrendingItem] {
        let now = Date()
        if let cache = trendingTVCache, now.timeIntervalSince(cache.date) < Self.trendingCacheTTL {
            return cache.items
        }
        let url = URL(string: "\(baseURL)/trending/tv/\(timeWindow)?api_key=\(apiKey)")!
        let response: TMDBTrendingResponse = try await decode(from: url)
        trendingTVCache = (date: now, items: response.results)
        return response.results
    }

    public func nowPlayingMovies(apiKey: String) async throws -> [TMDBTrendingItem] {
        let url = URL(string: "\(baseURL)/movie/now_playing?api_key=\(apiKey)&language=en-US&page=1")!
        let response: TMDBTrendingResponse = try await decode(from: url)
        return response.results
    }

    public func popularTV(apiKey: String) async throws -> [TMDBTrendingItem] {
        let url = URL(string: "\(baseURL)/tv/popular?api_key=\(apiKey)&language=en-US&page=1")!
        let response: TMDBTrendingResponse = try await decode(from: url)
        return response.results
    }

    public func topRatedMovies(apiKey: String) async throws -> [TMDBTrendingItem] {
        let url = URL(string: "\(baseURL)/movie/top_rated?api_key=\(apiKey)&language=en-US&page=1")!
        let response: TMDBTrendingResponse = try await decode(from: url)
        return response.results
    }

    public func topRatedTV(apiKey: String) async throws -> [TMDBTrendingItem] {
        let url = URL(string: "\(baseURL)/tv/top_rated?api_key=\(apiKey)&language=en-US&page=1")!
        let response: TMDBTrendingResponse = try await decode(from: url)
        return response.results
    }

    // MARK: - Genre Lists

    public func movieGenreMap(apiKey: String) async throws -> [Int: String] {
        let url = URL(string: "\(baseURL)/genre/movie/list?api_key=\(apiKey)&language=en")!
        let response: TMDBGenreListResponse = try await decode(from: url)
        return Dictionary(uniqueKeysWithValues: response.genres.map { ($0.id, $0.name) })
    }

    public func tvGenreMap(apiKey: String) async throws -> [Int: String] {
        let url = URL(string: "\(baseURL)/genre/tv/list?api_key=\(apiKey)&language=en")!
        let response: TMDBGenreListResponse = try await decode(from: url)
        return Dictionary(uniqueKeysWithValues: response.genres.map { ($0.id, $0.name) })
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
    public let imdbId: String?
    public let overview: String?
    public let voteAverage: Double?
    public let releaseDate: String?      // movie
    public let firstAirDate: String?     // tv
    public let genres: [TMDBGenre]?
    public let runtime: Int?             // movie
    public let numberOfSeasons: Int?     // tv
    public let tagline: String?
    public let status: String?
    public let backdropPath: String?

    enum CodingKeys: String, CodingKey {
        case id, overview, genres, runtime, tagline, status
        case imdbId = "imdb_id"
        case voteAverage = "vote_average"
        case releaseDate = "release_date"
        case firstAirDate = "first_air_date"
        case numberOfSeasons = "number_of_seasons"
        case backdropPath = "backdrop_path"
    }

    public var yearString: String? {
        let date = releaseDate ?? firstAirDate
        guard let date, date.count >= 4 else { return nil }
        return String(date.prefix(4))
    }

    public var backdropURL: URL? {
        backdropPath.flatMap { URL(string: "https://image.tmdb.org/t/p/w1280\($0)") }
    }
}

public struct TMDBGenre: Decodable, Sendable {
    public let id: Int
    public let name: String
}

// MARK: - Trending Item

public struct TMDBTrendingItem: Decodable, Identifiable, Sendable {
    public let id: Int
    public let title: String?          // movies
    public let name: String?           // TV
    public let overview: String?
    public let posterPath: String?
    public let backdropPath: String?
    public let voteAverage: Double?
    public let voteCount: Int?
    public let releaseDate: String?
    public let firstAirDate: String?
    public let mediaType: String?
    public let genreIds: [Int]?

    enum CodingKeys: String, CodingKey {
        case id, title, name, overview, mediaType = "media_type"
        case posterPath   = "poster_path"
        case backdropPath = "backdrop_path"
        case voteAverage  = "vote_average"
        case voteCount    = "vote_count"
        case releaseDate  = "release_date"
        case firstAirDate = "first_air_date"
        case genreIds     = "genre_ids"
    }

    public var displayTitle: String { title ?? name ?? "Unknown" }

    public var posterURL: URL? {
        guard let p = posterPath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w342\(p)")
    }
    public var backdropURL: URL? {
        guard let b = backdropPath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w1280\(b)")
    }
    public var yearString: String? {
        let d = releaseDate ?? firstAirDate
        guard let d, d.count >= 4 else { return nil }
        return String(d.prefix(4))
    }
    /// Alias for `yearString` — used by UI components.
    public var releaseYear: String? { yearString }

    /// Returns the first matching genre name from the provided genre map.
    public func primaryGenre(from genreMap: [Int: String]) -> String? {
        genreIds?.compactMap { genreMap[$0] }.first
    }
}

private struct TMDBTrendingResponse: Decodable {
    let results: [TMDBTrendingItem]
}

private struct TMDBGenreListResponse: Decodable {
    let genres: [TMDBGenre]
}

// MARK: - Content Ratings

private struct TMDBReleaseDatesResponse: Decodable {
    struct Country: Decodable {
        let iso31661: String
        struct ReleaseDate: Decodable {
            let certification: String
            enum CodingKeys: String, CodingKey { case certification }
        }
        let releaseDates: [ReleaseDate]
        enum CodingKeys: String, CodingKey {
            case iso31661 = "iso_3166_1"
            case releaseDates = "release_dates"
        }
    }
    let results: [Country]
}

private struct TMDBContentRatingsResponse: Decodable {
    struct Rating: Decodable {
        let iso31661: String
        let rating: String
        enum CodingKeys: String, CodingKey {
            case iso31661 = "iso_3166_1"
            case rating
        }
    }
    let results: [Rating]
    // MARK: - Trending

    public func trendingMovies(timeWindow: String = "week", apiKey: String) async throws -> [TMDBTrendingItem] {
        let now = Date()
        if let cache = trendingMoviesCache, now.timeIntervalSince(cache.date) < Self.trendingCacheTTL {
            return cache.items
        }
        let url = URL(string: "\(baseURL)/trending/movie/\(timeWindow)?api_key=\(apiKey)")!
        let response: TMDBTrendingResponse = try await decode(from: url)
        trendingMoviesCache = (date: now, items: response.results)
        return response.results
    }

    public func trendingTV(timeWindow: String = "week", apiKey: String) async throws -> [TMDBTrendingItem] {
        let now = Date()
        if let cache = trendingTVCache, now.timeIntervalSince(cache.date) < Self.trendingCacheTTL {
            return cache.items
        }
        let url = URL(string: "\(baseURL)/trending/tv/\(timeWindow)?api_key=\(apiKey)")!
        let response: TMDBTrendingResponse = try await decode(from: url)
        trendingTVCache = (date: now, items: response.results)
        return response.results
    }

    public func nowPlayingMovies(apiKey: String) async throws -> [TMDBTrendingItem] {
        let url = URL(string: "\(baseURL)/movie/now_playing?api_key=\(apiKey)&language=en-US&page=1")!
        let response: TMDBTrendingResponse = try await decode(from: url)
        return response.results
    }

    public func popularTV(apiKey: String) async throws -> [TMDBTrendingItem] {
        let url = URL(string: "\(baseURL)/tv/popular?api_key=\(apiKey)&language=en-US&page=1")!
        let response: TMDBTrendingResponse = try await decode(from: url)
        return response.results
    }

    public func topRatedMovies(apiKey: String) async throws -> [TMDBTrendingItem] {
        let url = URL(string: "\(baseURL)/movie/top_rated?api_key=\(apiKey)&language=en-US&page=1")!
        let response: TMDBTrendingResponse = try await decode(from: url)
        return response.results
    }

    public func topRatedTV(apiKey: String) async throws -> [TMDBTrendingItem] {
        let url = URL(string: "\(baseURL)/tv/top_rated?api_key=\(apiKey)&language=en-US&page=1")!
        let response: TMDBTrendingResponse = try await decode(from: url)
        return response.results
    }

    // MARK: - Genre Lists

    public func movieGenreMap(apiKey: String) async throws -> [Int: String] {
        let url = URL(string: "\(baseURL)/genre/movie/list?api_key=\(apiKey)&language=en")!
        let response: TMDBGenreListResponse = try await decode(from: url)
        return Dictionary(uniqueKeysWithValues: response.genres.map { ($0.id, $0.name) })
    }

    public func tvGenreMap(apiKey: String) async throws -> [Int: String] {
        let url = URL(string: "\(baseURL)/genre/tv/list?api_key=\(apiKey)&language=en")!
        let response: TMDBGenreListResponse = try await decode(from: url)
        return Dictionary(uniqueKeysWithValues: response.genres.map { ($0.id, $0.name) })
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
    public let imdbId: String?
    public let overview: String?
    public let voteAverage: Double?
    public let releaseDate: String?      // movie
    public let firstAirDate: String?     // tv
    public let genres: [TMDBGenre]?
    public let runtime: Int?             // movie
    public let numberOfSeasons: Int?     // tv
    public let tagline: String?
    public let status: String?
    public let backdropPath: String?

    enum CodingKeys: String, CodingKey {
        case id, overview, genres, runtime, tagline, status
        case imdbId = "imdb_id"
        case voteAverage = "vote_average"
        case releaseDate = "release_date"
        case firstAirDate = "first_air_date"
        case numberOfSeasons = "number_of_seasons"
        case backdropPath = "backdrop_path"
    }

    public var yearString: String? {
        let date = releaseDate ?? firstAirDate
        guard let date, date.count >= 4 else { return nil }
        return String(date.prefix(4))
    }

    public var backdropURL: URL? {
        backdropPath.flatMap { URL(string: "https://image.tmdb.org/t/p/w1280\($0)") }
    }
}

public struct TMDBGenre: Decodable, Sendable {
    public let id: Int
    public let name: String
}

// MARK: - Cast

public struct TMDBCastMember: Decodable, Sendable {
    public let id: Int
    public let name: String
    public let character: String?
    public let profilePath: String?

    public var profileURL: URL? {
        profilePath.flatMap { URL(string: "https://image.tmdb.org/t/p/w185\($0)") }
    }

    enum CodingKeys: String, CodingKey {
        case id, name, character
        case profilePath = "profile_path"
    }
}

private struct TMDBCreditsResponse: Decodable {
    let cast: [TMDBCastMember]
}

// MARK: - Similar

public struct TMDBSimilarItem: Identifiable, Decodable, Sendable {
    public let id: Int
    public let title: String?
    public let name: String?
    public let posterPath: String?

    public var displayTitle: String { title ?? name ?? "Unknown" }
    public var posterURL: URL? {
        posterPath.flatMap { URL(string: "https://image.tmdb.org/t/p/w342\($0)") }
    }

    enum CodingKeys: String, CodingKey {
        case id, title, name
        case posterPath = "poster_path"
    }
}

private struct TMDBSimilarResponse: Decodable {
    let results: [TMDBSimilarItem]
}

// MARK: - Trending

public struct TMDBTrendingItem: Identifiable, Decodable, Sendable {
    public let id: Int
    public let title: String?
    public let name: String?
    public let posterPath: String?
    public let backdropPath: String?
    public let genreIds: [Int]?
    public let voteAverage: Double?
    public let voteCount: Int?
    public let overview: String?
    public let releaseDate: String?   // "YYYY-MM-DD" for movies
    public let firstAirDate: String?  // "YYYY-MM-DD" for TV

    public var displayTitle: String { title ?? name ?? "Unknown" }
    public var posterURL: URL? {
        posterPath.flatMap { URL(string: "https://image.tmdb.org/t/p/w342\($0)") }
    }
    public var backdropURL: URL? {
        backdropPath.flatMap { URL(string: "https://image.tmdb.org/t/p/w780\($0)") }
    }
    public func primaryGenre(from map: [Int: String]) -> String? {
        genreIds?.compactMap { map[$0] }.first
    }
    /// Returns the 4-digit year string, e.g. "2024"
    public var releaseYear: String? {
        let dateStr = releaseDate ?? firstAirDate ?? ""
        guard dateStr.count >= 4 else { return nil }
        return String(dateStr.prefix(4))
    }

    enum CodingKeys: String, CodingKey {
        case id, title, name, overview
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
        case genreIds = "genre_ids"
        case voteAverage = "vote_average"
        case voteCount = "vote_count"
        case releaseDate = "release_date"
        case firstAirDate = "first_air_date"
    }
}

private struct TMDBTrendingResponse: Decodable {
    let results: [TMDBTrendingItem]
}

private struct TMDBGenreListResponse: Decodable {
    let genres: [TMDBGenre]
}

// MARK: - Content Ratings

private struct TMDBReleaseDatesResponse: Decodable {
    struct Country: Decodable {
        let iso31661: String
        struct ReleaseDate: Decodable {
            let certification: String
            enum CodingKeys: String, CodingKey { case certification }
        }
        let releaseDates: [ReleaseDate]
        enum CodingKeys: String, CodingKey {
            case iso31661 = "iso_3166_1"
            case releaseDates = "release_dates"
        }
    }
    let results: [Country]
}

private struct TMDBContentRatingsResponse: Decodable {
    struct Rating: Decodable {
        let iso31661: String
        let rating: String
        enum CodingKeys: String, CodingKey {
            case iso31661 = "iso_3166_1"
            case rating
        }
    }
    let results: [Rating]
}
