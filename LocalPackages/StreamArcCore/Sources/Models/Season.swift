import Foundation

public struct Season: Identifiable, Hashable, Sendable {
    public let id: String
    public var seasonNumber: Int
    public var episodes: [Episode]
    public var posterURL: String?

    public init(
        id: String = UUID().uuidString,
        seasonNumber: Int,
        episodes: [Episode] = [],
        posterURL: String? = nil
    ) {
        self.id = id
        self.seasonNumber = seasonNumber
        self.episodes = episodes
        self.posterURL = posterURL
    }
}
