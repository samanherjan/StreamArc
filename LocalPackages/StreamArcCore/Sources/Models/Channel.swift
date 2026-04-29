import Foundation

public struct Channel: Identifiable, Hashable, Sendable {
    public let id: String
    public var name: String
    public var groupTitle: String
    public var logoURL: String?
    public var streamURL: String
    /// Alternate stream URLs tried in order after the primary fails all retries.
    public var fallbackURLs: [String]
    public var epgId: String?
    public var currentProgram: EPGProgram?
    public var nextProgram: EPGProgram?

    public init(
        id: String = UUID().uuidString,
        name: String,
        groupTitle: String = "",
        logoURL: String? = nil,
        streamURL: String,
        fallbackURLs: [String] = [],
        epgId: String? = nil
    ) {
        self.id = id
        self.name = name
        self.groupTitle = groupTitle
        self.logoURL = logoURL
        self.streamURL = streamURL
        self.fallbackURLs = fallbackURLs
        self.epgId = epgId
    }
}
