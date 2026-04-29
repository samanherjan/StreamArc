import Foundation
import SwiftData

// SwiftData-backed favorite — stores a content ID and type tag.
@Model
final class FavoriteItem {
    var contentId: String
    var contentType: String   // "channel" | "vod" | "series"
    var title: String
    var imageURL: String?
    var addedAt: Date
    /// Whether this channel is pinned in the quick-access bar.
    var isPinned: Bool
    /// Sort order within the pin bar (lower = further left).
    var pinnedOrder: Int

    init(contentId: String, contentType: String, title: String, imageURL: String? = nil) {
        self.contentId = contentId
        self.contentType = contentType
        self.title = title
        self.imageURL = imageURL
        self.addedAt = .now
        self.isPinned = false
        self.pinnedOrder = 0
    }
}

@MainActor
final class FavoritesManager {

    private let modelContext: ModelContext

    // Free-tier cap (11th favorite triggers paywall)
    static let freeTierCap = 10
    static let freePinCap = 4
    static let premiumPinCap = 8

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func isFavorite(contentId: String) -> Bool {
        (try? modelContext.fetch(
            FetchDescriptor<FavoriteItem>(
                predicate: #Predicate { $0.contentId == contentId }
            )
        ))?.isEmpty == false ? true : false
    }

    func addFavorite(contentId: String, contentType: String, title: String, imageURL: String? = nil) throws {
        guard !isFavorite(contentId: contentId) else { return }
        let item = FavoriteItem(contentId: contentId, contentType: contentType, title: title, imageURL: imageURL)
        modelContext.insert(item)
        try modelContext.save()
    }

    func removeFavorite(contentId: String) throws {
        let items = try modelContext.fetch(
            FetchDescriptor<FavoriteItem>(
                predicate: #Predicate { $0.contentId == contentId }
            )
        )
        items.forEach { modelContext.delete($0) }
        try modelContext.save()
    }

    func toggleFavorite(contentId: String, contentType: String, title: String, imageURL: String? = nil) throws {
        if isFavorite(contentId: contentId) {
            try removeFavorite(contentId: contentId)
        } else {
            try addFavorite(contentId: contentId, contentType: contentType, title: title, imageURL: imageURL)
        }
    }

    func allFavorites() throws -> [FavoriteItem] {
        var desc = FetchDescriptor<FavoriteItem>(sortBy: [SortDescriptor(\.addedAt, order: .reverse)])
        desc.fetchLimit = 200
        return try modelContext.fetch(desc)
    }

    func totalCount() -> Int {
        (try? modelContext.fetchCount(FetchDescriptor<FavoriteItem>())) ?? 0
    }

    // MARK: - Pin Bar

    func pinnedItems() throws -> [FavoriteItem] {
        let desc = FetchDescriptor<FavoriteItem>(
            predicate: #Predicate { $0.isPinned == true },
            sortBy: [SortDescriptor(\.pinnedOrder)]
        )
        return try modelContext.fetch(desc)
    }

    func isChannelPinned(contentId: String) -> Bool {
        let items = try? modelContext.fetch(
            FetchDescriptor<FavoriteItem>(predicate: #Predicate { $0.contentId == contentId })
        )
        return items?.first?.isPinned == true
    }

    func pinChannel(contentId: String, title: String, imageURL: String?, isPremium: Bool) throws {
        let cap = isPremium ? Self.premiumPinCap : Self.freePinCap
        let currentPinCount = (try? pinnedItems())?.count ?? 0
        guard currentPinCount < cap else { return }

        // Ensure item exists in favorites first
        if !isFavorite(contentId: contentId) {
            try addFavorite(contentId: contentId, contentType: "channel", title: title, imageURL: imageURL)
        }
        guard let item = try modelContext.fetch(
            FetchDescriptor<FavoriteItem>(predicate: #Predicate { $0.contentId == contentId })
        ).first else { return }
        let maxOrder = (try? pinnedItems())?.last?.pinnedOrder ?? 0
        item.isPinned = true
        item.pinnedOrder = maxOrder + 1
        try modelContext.save()
    }

    func unpinChannel(contentId: String) throws {
        guard let item = try modelContext.fetch(
            FetchDescriptor<FavoriteItem>(predicate: #Predicate { $0.contentId == contentId })
        ).first else { return }
        item.isPinned = false
        try modelContext.save()
    }
}
