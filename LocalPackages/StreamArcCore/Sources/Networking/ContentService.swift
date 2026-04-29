import Foundation

/// Unified result from any IPTV source.
public struct ContentResult: Sendable {
    public var channels: [Channel]
    public var vodItems: [VODItem]
    public var series: [Series]

    public init(channels: [Channel] = [], vodItems: [VODItem] = [], series: [Series] = []) {
        self.channels = channels
        self.vodItems = vodItems
        self.series = series
    }
}

/// Protocol abstracting content loading from any IPTV source.
/// Each source type (M3U, Xtream, Stalker, Enigma2) provides an adapter.
public protocol ContentService: Sendable {
    func loadContent() async throws -> ContentResult
}

// MARK: - M3U Adapter

public struct M3UContentService: ContentService {
    private let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func loadContent() async throws -> ContentResult {
        let result = try await M3UParser.parse(url: url)
        return ContentResult(channels: result.channels, vodItems: result.vodItems)
    }
}

// MARK: - Xtream Adapter

public struct XtreamContentService: ContentService {
    private let config: XtreamClient.Config

    public init(baseURL: String, username: String, password: String) {
        self.config = .init(baseURL: baseURL, username: username, password: password)
    }

    public func loadContent() async throws -> ContentResult {
        let client = XtreamClient(config: config)
        async let ch  = client.asChannels()
        async let vod = client.asVODItems()
        async let ser = client.asSeries()
        return try await ContentResult(channels: ch, vodItems: vod, series: ser)
    }
}

// MARK: - Stalker Adapter

public struct StalkerContentService: ContentService {
    private let config: StalkerClient.Config

    public init(portalURL: String, macAddress: String) {
        self.config = .init(portalURL: portalURL, macAddress: macAddress)
    }

    public func loadContent() async throws -> ContentResult {
        let client = StalkerClient(config: config)
        try await client.authenticate()

        // Channels first (fastest)
        let channels = try await client.channels()

        // VOD and series — don't fail the whole load if these timeout
        let vodItems = await loadStalkerVOD(client: client)
        let series = await loadStalkerSeries(client: client)

        return ContentResult(channels: channels, vodItems: vodItems, series: series)
    }

    private func loadStalkerVOD(client: StalkerClient) async -> [VODItem] {
        guard let categories = try? await client.vodCategories() else { return [] }
        var allVOD: [VODItem] = []
        for batch in categories.chunked(into: 3) {
            let batchResults = await withTaskGroup(of: [VODItem].self) { group in
                for cat in batch {
                    group.addTask {
                        guard let items = try? await client.vodItems(categoryId: cat.id) else { return [] }
                        return items.map { item -> VODItem in
                            var v = item
                            v.groupTitle = cat.title
                            return v
                        }
                    }
                }
                var results: [VODItem] = []
                for await items in group { results.append(contentsOf: items) }
                return results
            }
            allVOD.append(contentsOf: batchResults)
        }
        return allVOD
    }

    private func loadStalkerSeries(client: StalkerClient) async -> [Series] {
        guard let categories = try? await client.seriesCategories() else { return [] }
        var all: [Series] = []
        for batch in categories.chunked(into: 3) {
            let batchResults = await withTaskGroup(of: [Series].self) { group in
                for cat in batch {
                    group.addTask {
                        guard let items = try? await client.seriesItems(categoryId: cat.id) else { return [] }
                        return items.map { item -> Series in
                            var s = item
                            s.groupTitle = cat.title
                            return s
                        }
                    }
                }
                var results: [Series] = []
                for await items in group { results.append(contentsOf: items) }
                return results
            }
            all.append(contentsOf: batchResults)
        }
        return all
    }
}

// MARK: - Enigma2 Adapter

public struct Enigma2ContentService: ContentService {
    private let config: Enigma2Client.Config

    public init(baseURL: String) {
        self.config = .init(baseURL: baseURL)
    }

    public func loadContent() async throws -> ContentResult {
        let client = Enigma2Client(config: config)
        let bouquets = try await client.bouquets()
        var allChannels: [Channel] = []
        for bouquet in bouquets.prefix(20) {
            let ch = try await client.services(bouquetRef: bouquet.id)
            allChannels.append(contentsOf: ch)
        }
        return ContentResult(channels: allChannels)
    }
}
