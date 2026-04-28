import StreamArcCore
import Foundation

@MainActor
@Observable
final class SearchViewModel {
    var query = ""
    var selectedResult: SearchResult?

    enum SearchResult: Identifiable {
        case channel(Channel)
        case vod(VODItem)
        case series(Series)

        var id: String {
            switch self {
            case .channel(let c):  return "ch_\(c.id)"
            case .vod(let v):      return "vod_\(v.id)"
            case .series(let s):   return "ser_\(s.id)"
            }
        }
        var title: String {
            switch self {
            case .channel(let c):  return c.name
            case .vod(let v):      return v.title
            case .series(let s):   return s.title
            }
        }
        var imageURL: String? {
            switch self {
            case .channel(let c):  return c.logoURL
            case .vod(let v):      return v.posterURL
            case .series(let s):   return s.posterURL
            }
        }
        var typeLabel: String {
            switch self {
            case .channel:  return "Live TV"
            case .vod:      return "Movie"
            case .series:   return "Series"
            }
        }
        var systemImage: String {
            switch self {
            case .channel:  return "tv"
            case .vod:      return "film"
            case .series:   return "tv.and.mediabox"
            }
        }
    }

    func results(channels: [Channel], vodItems: [VODItem], series: [Series]) -> [SearchResult] {
        guard query.count >= 2 else { return [] }
        let q = query.lowercased()
        var results: [SearchResult] = []
        results += channels.filter  { $0.name.lowercased().contains(q) }.prefix(30).map { .channel($0) }
        results += vodItems.filter  { $0.title.lowercased().contains(q) }.prefix(30).map { .vod($0) }
        results += series.filter    { $0.title.lowercased().contains(q) }.prefix(20).map { .series($0) }
        return results
    }
}
