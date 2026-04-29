import Foundation

public enum VODType: String, Codable, Sendable {
    case movie, series
}

public struct VODItem: Identifiable, Hashable, Sendable {
    public let id: String
    public var title: String
    public var year: Int?
    public var posterURL: String?
    public var streamURL: String
    public var tmdbId: Int?
    public var type: VODType
    public var groupTitle: String
    public var rating: String?
    public var description: String?
    /// Custom HTTP headers required by this stream (User-Agent, Referer, Origin).
    public var httpHeaders: [String: String] = [:]

    public init(
        id: String = UUID().uuidString,
        title: String,
        year: Int? = nil,
        posterURL: String? = nil,
        streamURL: String,
        tmdbId: Int? = nil,
        type: VODType = .movie,
        groupTitle: String = ""
    ) {
        self.id = id
        self.title = title
        self.year = year
        self.posterURL = posterURL
        self.streamURL = streamURL
        self.tmdbId = tmdbId
        self.type = type
        self.groupTitle = groupTitle
    }
}
