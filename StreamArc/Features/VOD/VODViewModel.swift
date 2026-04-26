import Foundation

@MainActor
@Observable
final class VODViewModel {

    var searchText = ""
    var selectedGroup: String?

    private let freeTierVODCap    = 50
    private let freeTierSeriesCap = 0   // Series entirely paywalled for free users

    func filteredMovies(from items: [VODItem], isPremium: Bool) -> [VODItem] {
        let movies = items.filter { $0.type == .movie }
        let capped = isPremium ? movies : Array(movies.prefix(freeTierVODCap))
        guard !searchText.isEmpty else {
            if let group = selectedGroup {
                return capped.filter { $0.groupTitle == group }
            }
            return capped
        }
        return capped.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    func filteredSeries(from items: [Series], isPremium: Bool) -> [Series] {
        guard isPremium else { return [] }
        guard !searchText.isEmpty else { return items }
        return items.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    func groups(from items: [VODItem]) -> [String] {
        let groups = items.compactMap { $0.groupTitle.isEmpty ? nil : $0.groupTitle }
        return Array(Set(groups)).sorted()
    }

    func isAtFreeCap(items: [VODItem], isPremium: Bool) -> Bool {
        !isPremium && items.filter({ $0.type == .movie }).count > freeTierVODCap
    }
}
