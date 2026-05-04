import Foundation
import SwiftData
import StreamArcCore

@Model
final class WatchHistoryEntry {
    var contentId: String
    var contentType: String    // "channel" | "vod" | "episode"
    var title: String
    var imageURL: String?
    var lastPosition: Double   // seconds
    var duration: Double       // seconds (0 = live/unknown)
    var watchedAt: Date

    // Series-specific fields (nil for movies/channels)
    var seriesId: String?
    var seasonNumber: Int = 0
    var episodeNumber: Int = 0

    @Transient var progress: Double {
        guard duration > 0 else { return 0 }
        return min(1, lastPosition / duration)
    }

    @Transient var isWatched: Bool { progress >= 0.9 }

    init(contentId: String, contentType: String, title: String, imageURL: String? = nil,
         lastPosition: Double = 0, duration: Double = 0,
         seriesId: String? = nil, seasonNumber: Int = 0, episodeNumber: Int = 0) {
        self.contentId = contentId
        self.contentType = contentType
        self.title = title
        self.imageURL = imageURL
        self.lastPosition = lastPosition
        self.duration = duration
        self.watchedAt = .now
        self.seriesId = seriesId
        self.seasonNumber = seasonNumber
        self.episodeNumber = episodeNumber
    }
}

@MainActor
final class WatchHistoryManager {

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func record(contentId: String, contentType: String, title: String,
                imageURL: String?, position: Double, duration: Double,
                seriesId: String? = nil, seasonNumber: Int = 0, episodeNumber: Int = 0) throws {
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
                lastPosition: position, duration: duration,
                seriesId: seriesId, seasonNumber: seasonNumber, episodeNumber: episodeNumber
            )
            modelContext.insert(entry)
        }
        try modelContext.save()
    }

    func entry(for contentId: String) -> WatchHistoryEntry? {
        try? modelContext.fetch(
            FetchDescriptor<WatchHistoryEntry>(
                predicate: #Predicate { $0.contentId == contentId }
            )
        ).first
    }

    func lastPosition(for contentId: String) -> Double {
        entry(for: contentId)?.lastPosition ?? 0
    }

    func progress(for contentId: String) -> Double {
        entry(for: contentId)?.progress ?? 0
    }

    func continueEpisode(seriesId: String, in seasons: [Season]) -> (episode: Episode, startPosition: Double)? {
        let allEntries = (try? modelContext.fetch(
            FetchDescriptor<WatchHistoryEntry>(
                predicate: #Predicate { $0.seriesId == seriesId },
                sortBy: [SortDescriptor(\.watchedAt, order: .reverse)]
            )
        )) ?? []

        if let inProgress = allEntries.first(where: { !$0.isWatched && $0.lastPosition > 5 }) {
            for season in seasons {
                for episode in season.episodes {
                    if episode.id == inProgress.contentId {
                        return (episode, inProgress.lastPosition)
                    }
                }
            }
        }

        let watchedIds = Set(allEntries.filter { $0.isWatched }.map { $0.contentId })
        for season in seasons.sorted(by: { $0.seasonNumber < $1.seasonNumber }) {
            for episode in season.episodes {
                if !watchedIds.contains(episode.id) {
                    return (episode, 0)
                }
            }
        }

        return nil
    }

    func recentItems(limit: Int = 20) throws -> [WatchHistoryEntry] {
        var desc = FetchDescriptor<WatchHistoryEntry>(
            sortBy: [SortDescriptor(\.watchedAt, order: .reverse)]
        )
        desc.fetchLimit = limit
        return try modelContext.fetch(desc)
    }

    func continueWatchingItems(limit: Int = 10) throws -> [WatchHistoryEntry] {
        let desc = FetchDescriptor<WatchHistoryEntry>(
            sortBy: [SortDescriptor(\.watchedAt, order: .reverse)]
        )
        let all = try modelContext.fetch(desc)
        return all.filter {
            $0.contentType != "channel" &&
            $0.lastPosition > 5 &&
            !$0.isWatched
        }.prefix(limit).map { $0 }
    }

    func clear() throws {
        try modelContext.delete(model: WatchHistoryEntry.self)
        try modelContext.save()
    }

    func queueNextEpisode(afterSeason seasonNumber: Int, episode episodeNumber: Int,
                          seriesId: String, in seasons: [Season]) {
        let sorted = seasons.sorted { $0.seasonNumber < $1.seasonNumber }

        guard let seasonIdx = sorted.firstIndex(where: { $0.seasonNumber == seasonNumber }) else { return }
        let season = sorted[seasonIdx]
        let sortedEps = season.episodes.sorted { $0.episodeNumber < $1.episodeNumber }

        var nextEpisode: Episode?
        var nextSeasonNumber = seasonNumber

        if let epIdx = sortedEps.firstIndex(where: { $0.episodeNumber == episodeNumber }),
           epIdx + 1 < sortedEps.count {
            nextEpisode = sortedEps[epIdx + 1]
        } else if seasonIdx + 1 < sorted.count {
            let nextSeason = sorted[seasonIdx + 1]
            nextSeasonNumber = nextSeason.seasonNumber
            nextEpisode = nextSeason.episodes.sorted { $0.episodeNumber < $1.episodeNumber }.first
        }

        guard let ep = nextEpisode else { return }

        // Capture as plain String — #Predicate cannot reference key paths of captured objects
        let epId: String = ep.id
        let existing = try? modelContext.fetch(
            FetchDescriptor<WatchHistoryEntry>(
                predicate: #Predicate { $0.contentId == epId }
            )
        ).first
        guard existing == nil else { return }

        let histEntry = WatchHistoryEntry(
            contentId: ep.id,
            contentType: "episode",
            title: ep.title,
            imageURL: ep.posterURL,
            lastPosition: 0,
            duration: ep.duration ?? 0,
            seriesId: seriesId,
            seasonNumber: nextSeasonNumber,
            episodeNumber: ep.episodeNumber
        )
        modelContext.insert(histEntry)
        try? modelContext.save()
    }
}
