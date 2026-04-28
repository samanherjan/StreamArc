import Foundation

public struct Series: Identifiable, Hashable, Sendable {
    public let id: String
    public var title: String
    public var posterURL: String?
    public var tmdbId: Int?
    public var seasons: [Season]
    public var description: String?
    public var rating: String?
    public var year: Int?
    public var groupTitle: String?

    public init(
        id: String = UUID().uuidString,
        title: String,
        posterURL: String? = nil,
        tmdbId: Int? = nil,
        seasons: [Season] = [],
        groupTitle: String? = nil
    ) {
        self.id = id
        self.title = title
        self.posterURL = posterURL
        self.tmdbId = tmdbId
        self.seasons = seasons
        self.groupTitle = groupTitle
    }
}
