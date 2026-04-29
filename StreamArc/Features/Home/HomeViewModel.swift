import StreamArcCore
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
            let service = Self.makeContentService(for: profile)
            let result = try await service.loadContent()
            channels = result.channels
            vodItems = result.vodItems
            series   = result.series

            // Show content immediately — EPG loads in background
            loadState = .loaded
            profile.lastLoadedAt = .now
            await loadEPG(profile: profile)
            applyEPG()
        } catch {
            loadState = .error(error.localizedDescription)
        }
    }

    // MARK: - Content Service Factory

    private static func makeContentService(for profile: Profile) -> ContentService {
        switch profile.sourceType {
        case .m3u:
            guard let urlStr = profile.m3uURL, let url = URL(string: urlStr) else {
                return FailingContentService(error: URLError(.badURL))
            }
            return M3UContentService(url: url)
        case .xtream:
            guard let base = profile.xtreamURL,
                  let user = profile.xtreamUsername,
                  let pass = profile.xtreamPassword else {
                return FailingContentService(error: URLError(.badURL))
            }
            return XtreamContentService(baseURL: base, username: user, password: pass)
        case .stalker:
            guard let portal = profile.portalURL,
                  let mac    = profile.macAddress else {
                return FailingContentService(error: URLError(.badURL))
            }
            return StalkerContentService(portalURL: portal, macAddress: mac)
        case .enigma2:
            guard let url = profile.enigma2URL else {
                return FailingContentService(error: URLError(.badURL))
            }
            return Enigma2ContentService(baseURL: url)
        }
    }

    // MARK: - EPG

    private func loadEPG(profile: Profile) async {
        let epgURLStr = profile.epgURL ?? ""
        guard !epgURLStr.isEmpty, let epgURL = URL(string: epgURLStr) else { return }

        // Check in-memory cache first
        if let cache = epgCache,
           cache.url == epgURLStr,
           Date.now.timeIntervalSince(cache.date) < Self.epgCacheTTL {
            epgMap = buildEPGMap(from: cache.programs)
            return
        }

        // Check disk cache
        if let diskCached = await EPGCacheManager.shared.cached(for: epgURLStr) {
            epgCache = (epgURLStr, Date.now, diskCached)
            epgMap = buildEPGMap(from: diskCached)
            return
        }

        // Fetch fresh
        if let programs = try? await EPGParser.parse(url: epgURL) {
            epgCache = (epgURLStr, Date.now, programs)
            epgMap = buildEPGMap(from: programs)
            // Store to disk in background
            Task.detached(priority: .utility) {
                await EPGCacheManager.shared.store(programs, for: epgURLStr)
            }
        }
    }

    private func buildEPGMap(from programs: [EPGProgram]) -> [String: [EPGProgram]] {
        Dictionary(grouping: programs, by: \.channelId)
    }

    private func applyEPG() {
        let now = Date.now
        channels = channels.map { channel in
            var ch = channel
            let programs = epgMap[channel.epgId ?? channel.id] ?? []
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

    /// Clears both in-memory and disk EPG caches.
    func clearEPGCache() async {
        epgCache = nil
        epgMap = [:]
        await EPGCacheManager.shared.clearAll()
    }
}

// MARK: - Failing Service (for invalid configs)

private struct FailingContentService: ContentService {
    let error: Error
    func loadContent() async throws -> ContentResult { throw error }
}
