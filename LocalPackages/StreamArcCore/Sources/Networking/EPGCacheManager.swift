import Foundation

/// Disk-backed EPG cache with configurable TTL.
/// Stores EPG data as compressed JSON in the app's caches directory.
public actor EPGCacheManager {

    public static let shared = EPGCacheManager()

    private let ttl: TimeInterval
    private let cacheDir: URL

    public init(ttl: TimeInterval = 43_200) { // 12 hours default
        self.ttl = ttl
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        self.cacheDir = base.appendingPathComponent("StreamArc/EPGCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    private func cacheFile(for urlString: String) -> URL {
        let hash = urlString.data(using: .utf8)!.base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .prefix(64)
        return cacheDir.appendingPathComponent("\(hash).json")
    }

    private func metaFile(for urlString: String) -> URL {
        let hash = urlString.data(using: .utf8)!.base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .prefix(64)
        return cacheDir.appendingPathComponent("\(hash).meta")
    }

    /// Returns cached programs if the cache is still fresh.
    public func cached(for urlString: String) -> [EPGProgram]? {
        let meta = metaFile(for: urlString)
        let file = cacheFile(for: urlString)

        guard FileManager.default.fileExists(atPath: meta.path),
              FileManager.default.fileExists(atPath: file.path),
              let metaData = try? Data(contentsOf: meta),
              let timestamp = String(data: metaData, encoding: .utf8),
              let date = Double(timestamp) else { return nil }

        let age = Date.now.timeIntervalSince1970 - date
        guard age < ttl else { return nil }

        guard let data = try? Data(contentsOf: file),
              let programs = try? JSONDecoder().decode([CodableEPGProgram].self, from: data) else { return nil }
        return programs.map(\.asEPGProgram)
    }

    /// Store programs to disk cache.
    public func store(_ programs: [EPGProgram], for urlString: String) {
        let codable = programs.map(CodableEPGProgram.init)
        guard let data = try? JSONEncoder().encode(codable) else { return }
        try? data.write(to: cacheFile(for: urlString))
        let ts = "\(Date.now.timeIntervalSince1970)"
        try? ts.data(using: .utf8)?.write(to: metaFile(for: urlString))
    }

    /// Clears all cached EPG data.
    public func clearAll() {
        try? FileManager.default.removeItem(at: cacheDir)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }
}

// MARK: - Codable wrapper for EPGProgram (since it's a struct without Codable conformance)

private struct CodableEPGProgram: Codable {
    let id: String
    let channelId: String
    let title: String
    let startDate: Date
    let endDate: Date
    let description: String?

    init(_ p: EPGProgram) {
        self.id = p.id
        self.channelId = p.channelId
        self.title = p.title
        self.startDate = p.startDate
        self.endDate = p.endDate
        self.description = p.description
    }

    var asEPGProgram: EPGProgram {
        EPGProgram(id: id, channelId: channelId, title: title, startDate: startDate, endDate: endDate, description: description)
    }
}
