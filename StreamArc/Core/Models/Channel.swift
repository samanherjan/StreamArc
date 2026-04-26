import Foundation

public struct Channel: Identifiable, Hashable, Sendable {
    public let id: String
    public var name: String
    public var groupTitle: String
    public var logoURL: String?
    public var streamURL: String
    public var epgId: String?
    public var currentProgram: EPGProgram?
    public var nextProgram: EPGProgram?

    public init(
        id: String = UUID().uuidString,
        name: String,
        groupTitle: String = "",
        logoURL: String? = nil,
        streamURL: String,
        epgId: String? = nil
    ) {
        self.id = id
        self.name = name
        self.groupTitle = groupTitle
        self.logoURL = logoURL
        self.streamURL = streamURL
        self.epgId = epgId
    }
}
