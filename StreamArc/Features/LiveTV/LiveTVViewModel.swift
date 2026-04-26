import Foundation

@MainActor
@Observable
final class LiveTVViewModel {

    var searchText = ""
    var selectedGroup: String?
    var selectedChannel: Channel?

    private let freeTierChannelCap = 200

    func filteredChannels(from channels: [Channel], isPremium: Bool) -> [Channel] {
        let capped = isPremium ? channels : Array(channels.prefix(freeTierChannelCap))
        guard !searchText.isEmpty else {
            if let group = selectedGroup {
                return capped.filter { $0.groupTitle == group }
            }
            return capped
        }
        return capped.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    func groups(from channels: [Channel]) -> [String] {
        let groups = channels.compactMap { $0.groupTitle.isEmpty ? nil : $0.groupTitle }
        return Array(Set(groups)).sorted()
    }

    var isAtFreeCap: Bool = false

    func checkFreeCap(channels: [Channel], isPremium: Bool) {
        isAtFreeCap = !isPremium && channels.count > freeTierChannelCap
    }
}
