import Foundation

public struct EPGProgram: Identifiable, Hashable, Sendable {
    public let id: String
    public var channelId: String
    public var title: String
    public var startDate: Date
    public var endDate: Date
    public var description: String?
    public var category: String?
    public var posterURL: String?

    public var isCurrentlyAiring: Bool {
        let now = Date.now
        return now >= startDate && now < endDate
    }

    public var progress: Double {
        let now = Date.now
        let total = endDate.timeIntervalSince(startDate)
        let elapsed = now.timeIntervalSince(startDate)
        guard total > 0 else { return 0 }
        return max(0, min(1, elapsed / total))
    }

    public init(
        id: String = UUID().uuidString,
        channelId: String,
        title: String,
        startDate: Date,
        endDate: Date,
        description: String? = nil
    ) {
        self.id = id
        self.channelId = channelId
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.description = description
    }
}
