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

        // Load channels, VOD, and series concurrently for maximum speed
        async let channelsTask = client.channels()
        async let vodTask = loadStalkerVOD(client: client)
        async let seriesTask = loadStalkerSeries(client: client)

        let channels = try await channelsTask
        let vodItems = await vodTask
        let series = await seriesTask

        return ContentResult(channels: channels, vodItems: vodItems, series: series)
    }

    private func loadStalkerVOD(client: StalkerClient) async -> [VODItem] {
        guard let categories = try? await client.vodCategories() else { return [] }
        // Load all categories concurrently (up to 5 at a time)
        return await withTaskGroup(of: [VODItem].self) { group in
            var allVOD: [VODItem] = []
            var active = 0
            var catIterator = categories.makeIterator()

            // Seed with initial batch
            for _ in 0..<5 {
                guard let cat = catIterator.next() else { break }
                active += 1
                group.addTask {
                    guard let items = try? await client.vodItems(categoryId: cat.id) else { return [] }
                    return items.map { var v = $0; v.groupTitle = cat.title; return v }
                }
            }

            for await items in group {
                allVOD.append(contentsOf: items)
                active -= 1
                if let cat = catIterator.next() {
                    active += 1
                    group.addTask {
                        guard let items = try? await client.vodItems(categoryId: cat.id) else { return [] }
                        return items.map { var v = $0; v.groupTitle = cat.title; return v }
                    }
                }
            }
            return allVOD
        }
    }

    private func loadStalkerSeries(client: StalkerClient) async -> [Series] {
        guard let categories = try? await client.seriesCategories() else { return [] }
        return await withTaskGroup(of: [Series].self) { group in
            var all: [Series] = []
            var catIterator = categories.makeIterator()

            for _ in 0..<5 {
                guard let cat = catIterator.next() else { break }
                group.addTask {
                    guard let items = try? await client.seriesItems(categoryId: cat.id) else { return [] }
                    return items.map { var s = $0; s.groupTitle = cat.title; return s }
                }
            }

            for await items in group {
                all.append(contentsOf: items)
                if let cat = catIterator.next() {
                    group.addTask {
                        guard let items = try? await client.seriesItems(categoryId: cat.id) else { return [] }
                        return items.map { var s = $0; s.groupTitle = cat.title; return s }
                    }
                }
            }
            return all
        }
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
