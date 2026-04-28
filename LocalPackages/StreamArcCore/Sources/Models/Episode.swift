import Foundation

public struct Episode: Identifiable, Hashable, Sendable {
    public let id: String
    public var episodeNumber: Int
    public var title: String
    public var streamURL: String
    public var description: String?
    public var duration: TimeInterval?
    public var posterURL: String?

    public init(
        id: String = UUID().uuidString,
        episodeNumber: Int,
        title: String,
        streamURL: String
    ) {
        self.id = id
        self.episodeNumber = episodeNumber
        self.title = title
        self.streamURL = streamURL
    }
}
