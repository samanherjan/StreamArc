import Foundation
import SwiftData

@Model
final class WatchHistoryEntry {
    var contentId: String
    var contentType: String    // "channel" | "vod" | "series"
    var title: String
    var imageURL: String?
    var lastPosition: Double   // seconds
    var duration: Double       // seconds (0 = live/unknown)
    var watchedAt: Date

    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(1, lastPosition / duration)
    }

    init(contentId: String, contentType: String, title: String, imageURL: String? = nil,
         lastPosition: Double = 0, duration: Double = 0) {
        self.contentId = contentId
        self.contentType = contentType
        self.title = title
        self.imageURL = imageURL
        self.lastPosition = lastPosition
        self.duration = duration
        self.watchedAt = .now
    }
}

@MainActor
final class WatchHistoryManager {

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func record(contentId: String, contentType: String, title: String,
                imageURL: String?, position: Double, duration: Double) throws {
        // Update existing entry if present, otherwise insert
        if let existing = try? modelContext.fetch(
            FetchDescriptor<WatchHistoryEntry>(
                predicate: #Predicate { $0.contentId == contentId }
            )
        ).first {
            existing.lastPosition = position
            existing.duration = duration
            existing.watchedAt = .now
        } else {
            let entry = WatchHistoryEntry(
                contentId: contentId, contentType: contentType,
                title: title, imageURL: imageURL,
                lastPosition: position, duration: duration
            )
            modelContext.insert(entry)
        }
        try modelContext.save()
    }

    func lastPosition(for contentId: String) -> Double {
        (try? modelContext.fetch(
            FetchDescriptor<WatchHistoryEntry>(
                predicate: #Predicate { $0.contentId == contentId }
            )
        ).first?.lastPosition) ?? 0
    }

    func recentItems(limit: Int = 20) throws -> [WatchHistoryEntry] {
        var desc = FetchDescriptor<WatchHistoryEntry>(
            sortBy: [SortDescriptor(\.watchedAt, order: .reverse)]
        )
        desc.fetchLimit = limit
        return try modelContext.fetch(desc)
    }

    func clear() throws {
        try modelContext.delete(model: WatchHistoryEntry.self)
        try modelContext.save()
    }
}
