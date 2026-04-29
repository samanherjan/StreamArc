import Foundation
import SwiftData
import StreamArcCore

@Model
final class Profile {
    var id: String
    var name: String
    var sourceTypeRaw: String
    var isActive: Bool
    var lastLoadedAt: Date?
    var createdAt: Date

    // M3U
    var m3uURL: String?

    // Stalker / MAG
    var portalURL: String?
    var macAddress: String?

    // Xtream Codes
    var xtreamURL: String?
    var xtreamUsername: String?
    var xtreamPassword: String?

    // Enigma2
    var enigma2URL: String?

    // Shared optional
    var epgURL: String?

    /// Computed accessor for the strongly-typed SourceType.
    @Transient var sourceType: SourceType {
        get { SourceType(rawValue: sourceTypeRaw) ?? .m3u }
        set { sourceTypeRaw = newValue.rawValue }
    }

    init(
        id: String = UUID().uuidString,
        name: String,
        sourceType: SourceType,
        isActive: Bool = false,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.sourceTypeRaw = sourceType.rawValue
        self.isActive = isActive
        self.createdAt = createdAt
    }
}
