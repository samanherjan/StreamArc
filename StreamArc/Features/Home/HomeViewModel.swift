import Foundation
import SwiftData

enum LoadState: Equatable {
    case idle, loading, loaded, error(String)
}

@MainActor
@Observable
final class HomeViewModel {

    var channels: [Channel]  = []
    var vodItems: [VODItem]  = []
    var series:   [Series]   = []
    var epgMap:   [String: [EPGProgram]] = [:]
    var loadState: LoadState = .idle

    private var activeProfile: Profile?
    private var epgCache: (url: String, date: Date, programs: [EPGProgram])?
    private static let epgCacheTTL: TimeInterval = 43_200  // 12 hours

    // MARK: - Load

    func noActiveProfile() {
        loadState = .error("No active source. Go to Settings → Manage Sources and tap \"Use\" on a source.")
    }

    func load(profile: Profile) async {
        guard loadState != .loading else { return }
        activeProfile = profile
        loadState = .loading
        channels = []
        vodItems = []
        series   = []

        do {
            switch profile.sourceType {
            case .m3u:
                try await loadM3U(profile: profile)
            case .xtream:
                try await loadXtream(profile: profile)
            case .stalker:
                try await loadStalker(profile: profile)
            case .enigma2:
                try await loadEnigma2(profile: profile)
            }
            // Show content immediately — EPG loads in background
            loadState = .loaded
            await loadEPG(profile: profile)
            applyEPG()
        } catch {
            loadState = .error(error.localizedDescription)
        }
    }

    // MARK: - Source loaders

    private func loadM3U(profile: Profile) async throws {
        guard let urlStr = profile.m3uURL, let url = URL(string: urlStr) else {
            throw URLError(.badURL)
        }
        let result = try await M3UParser.parse(url: url)
        channels = result.channels
        vodItems = result.vodItems
    }

    private func loadXtream(profile: Profile) async throws {
        guard let base = profile.xtreamURL,
              let user = profile.xtreamUsername,
              let pass = profile.xtreamPassword else { throw URLError(.badURL) }
        let client = XtreamClient(config: .init(baseURL: base, username: user, password: pass))
        async let ch  = client.asChannels()
        async let vod = client.asVODItems()
        async let ser = client.asSeries()
        (channels, vodItems, series) = try await (ch, vod, ser)
    }

    private func loadStalker(profile: Profile) async throws {
        guard let portal = profile.portalURL,
              let mac    = profile.macAddress else { throw URLError(.badURL) }
        let client = StalkerClient(config: .init(portalURL: portal, macAddress: mac))
        try await client.authenticate()

        // Load channels first (fastest, shows UI immediately)
        channels = try await client.channels()

        // Then load VOD and series — don't fail the whole load if these timeout
        vodItems = (try? await loadStalkerVOD(client: client)) ?? []
        series   = (try? await loadStalkerSeries(client: client)) ?? []
    }

    /// Fetch VOD items with throttled concurrency (max 3 at a time)
    private func loadStalkerVOD(client: StalkerClient) async throws -> [VODItem] {
        let categories = try await client.vodCategories()
        var allVOD: [VODItem] = []

        // Process in batches of 3 to avoid overwhelming the portal
        for batch in categories.chunked(into: 3) {
            try await withThrowingTaskGroup(of: [VODItem].self) { group in
                for cat in batch {
                    group.addTask {
                        let items = try await client.vodItems(categoryId: cat.id)
                        return items.map { item -> VODItem in
                            var v = item
                            v.groupTitle = cat.title
                            return v
                        }
                    }
                }
                for try await items in group {
                    allVOD.append(contentsOf: items)
                }
            }
        }
        return allVOD
    }

    /// Fetch series items with throttled concurrency (max 3 at a time)
    private func loadStalkerSeries(client: StalkerClient) async throws -> [Series] {
        let categories = try await client.seriesCategories()
        var all: [Series] = []

        for batch in categories.chunked(into: 3) {
            try await withThrowingTaskGroup(of: [Series].self) { group in
                for cat in batch {
                    group.addTask {
                        let items = try await client.seriesItems(categoryId: cat.id)
                        return items.map { item -> Series in
                            var s = item
                            s.groupTitle = cat.title
                            return s
                        }
                    }
                }
                for try await items in group {
                    all.append(contentsOf: items)
                }
            }
        }
        return all
    }

    private func loadEnigma2(profile: Profile) async throws {
        guard let url = profile.enigma2URL else { throw URLError(.badURL) }
        let client = Enigma2Client(config: .init(baseURL: url))
        let bouquets = try await client.bouquets()
        var allChannels: [Channel] = []
        for bouquet in bouquets.prefix(20) {
            let ch = try await client.services(bouquetRef: bouquet.id)
            allChannels.append(contentsOf: ch)
        }
        channels = allChannels
    }

    // MARK: - EPG

    private func loadEPG(profile: Profile) async {
        let epgURLStr = profile.epgURL ?? ""
        guard !epgURLStr.isEmpty, let epgURL = URL(string: epgURLStr) else { return }

        // Return cached data if still fresh
        if let cache = epgCache,
           cache.url == epgURLStr,
           Date.now.timeIntervalSince(cache.date) < Self.epgCacheTTL {
            epgMap = buildEPGMap(from: cache.programs)
            return
        }

        if let programs = try? await EPGParser.parse(url: epgURL) {
            epgCache = (epgURLStr, Date.now, programs)
            epgMap = buildEPGMap(from: programs)
        }
    }

    private func buildEPGMap(from programs: [EPGProgram]) -> [String: [EPGProgram]] {
        Dictionary(grouping: programs, by: \.channelId)
    }

    private func applyEPG() {
        channels = channels.map { channel in
            var ch = channel
            let programs = epgMap[channel.epgId ?? channel.id] ?? []
            let now = Date.now
            ch.currentProgram = programs.first { $0.startDate <= now && $0.endDate > now }
            ch.nextProgram = programs.first { $0.startDate > now }
            return ch
        }
    }

    // MARK: - Helpers

    func channelGroups() -> [String: [Channel]] {
        Dictionary(grouping: channels, by: \.groupTitle)
    }

    func groupedVOD() -> [String: [VODItem]] {
        let movies = vodItems.filter { $0.type == .movie }
        return Dictionary(grouping: movies, by: \.groupTitle)
    }
}
