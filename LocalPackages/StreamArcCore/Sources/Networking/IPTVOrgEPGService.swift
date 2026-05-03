import Foundation

// MARK: - iptv-org/epg Auto-EPG Service
//
// Uses the public iptv-org API (https://iptv-org.github.io/api/) to:
//  1. Enrich channel epgIds by matching channel names to the iptv-org channel registry.
//  2. Auto-discover XMLTV guide URLs when no manual EPG URL is configured.

public actor IPTVOrgEPGService {

    public static let shared = IPTVOrgEPGService()

    // MARK: - API endpoints

    private static let channelsAPI = URL(string: "https://iptv-org.github.io/api/channels.json")!
    private static let guidesAPI   = URL(string: "https://iptv-org.github.io/api/guides.json")!

    // MARK: - In-memory registry cache

    /// iptv-org channel entry from channels.json
    private struct OrgChannel: Decodable {
        let id: String
        let name: String
        let alt_names: [String]
        let country: String
        let tvg_id: String?
    }

    /// iptv-org guide entry from guides.json
    private struct OrgGuide: Decodable {
        let channel: String   // iptv-org channel ID, e.g. "bbc1.uk"
        let site: String
        let lang: String
        let url: String
    }

    private var orgChannels: [OrgChannel]?
    private var orgGuides:   [OrgGuide]?
    /// normalizedName → iptv-org channel ID
    private var nameIndex: [String: String] = [:]

    // MARK: - Public API

    /// For each channel that has no `epgId`, try to find one from the iptv-org registry.
    /// Returns an updated copy of the array with enriched epgIds.
    public func enrichEpgIds(channels: [Channel]) async -> [Channel] {
        await ensureLoaded()
        return channels.map { ch in
            guard ch.epgId == nil || ch.epgId!.isEmpty else { return ch }
            var updated = ch
            if let matched = match(name: ch.name) {
                updated.epgId = matched
            }
            return updated
        }
    }

    /// Returns XMLTV guide URLs that cover the given set of channels.
    /// Picks at most one guide per channel, preferring English.
    public func guideURLs(for channels: [Channel]) async -> [URL] {
        await ensureLoaded()
        guard let guides = orgGuides else { return [] }

        // Collect iptv-org channel IDs we care about
        var targetIds = Set<String>()
        for ch in channels {
            if let epgId = ch.epgId, !epgId.isEmpty {
                targetIds.insert(epgId)
            } else if let matched = match(name: ch.name) {
                targetIds.insert(matched)
            }
        }

        // Group guides by channel id, prefer English
        var seen = Set<String>()   // guide URLs already included
        var selectedURLs: [URL] = []

        for id in targetIds {
            let candidates = guides.filter { $0.channel == id }
            // Prefer English, then any
            let pick = candidates.first(where: { $0.lang.hasPrefix("en") }) ?? candidates.first
            if let pick, !seen.contains(pick.url), let url = URL(string: pick.url) {
                seen.insert(pick.url)
                selectedURLs.append(url)
            }
        }

        return selectedURLs
    }

    // MARK: - Private helpers

    private func ensureLoaded() async {
        guard orgChannels == nil || orgGuides == nil else { return }
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadChannels() }
            group.addTask { await self.loadGuides() }
        }
        buildNameIndex()
    }

    private func loadChannels() async {
        guard orgChannels == nil else { return }
        if let data = try? await URLSession.shared.data(from: Self.channelsAPI).0,
           let decoded = try? JSONDecoder().decode([OrgChannel].self, from: data) {
            orgChannels = decoded
        }
    }

    private func loadGuides() async {
        guard orgGuides == nil else { return }
        if let data = try? await URLSession.shared.data(from: Self.guidesAPI).0,
           let decoded = try? JSONDecoder().decode([OrgGuide].self, from: data) {
            orgGuides = decoded
        }
    }

    private func buildNameIndex() {
        guard let channels = orgChannels else { return }
        nameIndex = [:]
        for ch in channels {
            nameIndex[normalized(ch.name)] = ch.id
            for alt in ch.alt_names {
                nameIndex[normalized(alt)] = ch.id
            }
            if let tvgId = ch.tvg_id {
                nameIndex[normalized(tvgId)] = ch.id
            }
        }
    }

    /// Tries exact normalized match then strips common suffixes (HD, FHD, SD, +1…)
    private func match(name: String) -> String? {
        let key = normalized(name)
        if let id = nameIndex[key] { return id }
        // Strip common suffixes and retry
        let stripped = key
            .replacingOccurrences(of: #"\s*(hd|fhd|uhd|4k|sd|\+1|\+2|plus\d?)$"#,
                                  with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        return nameIndex[stripped]
    }

    private func normalized(_ s: String) -> String {
        s.lowercased()
         .replacingOccurrences(of: #"[^a-z0-9\s]"#, with: "", options: .regularExpression)
         .trimmingCharacters(in: .whitespaces)
    }
}

// Allow Channel to be used (it's Sendable)
extension IPTVOrgEPGService: Sendable {}
