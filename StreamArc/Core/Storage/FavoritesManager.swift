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

    init(contentId: String, contentType: String, title: String, imageURL: String? = nil) {
        self.contentId = contentId
        self.contentType = contentType
        self.title = title
        self.imageURL = imageURL
        self.addedAt = .now
    }
}

@MainActor
final class FavoritesManager {

    private let modelContext: ModelContext

    // Free-tier cap (11th favorite triggers paywall)
    static let freeTierCap = 10

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
}
