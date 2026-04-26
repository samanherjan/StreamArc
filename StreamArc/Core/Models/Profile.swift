import Foundation
import SwiftData

@Model
final class Profile {
    var id: String
    var name: String
    var sourceType: SourceType
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

    init(
        id: String = UUID().uuidString,
        name: String,
        sourceType: SourceType,
        isActive: Bool = false,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.sourceType = sourceType
        self.isActive = isActive
        self.createdAt = createdAt
    }
}
