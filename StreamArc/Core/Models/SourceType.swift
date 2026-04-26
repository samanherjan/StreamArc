import Foundation

public enum SourceType: String, CaseIterable, Codable, Sendable {
    case m3u      = "M3U Playlist"
    case stalker  = "MAG / Stalker Portal"
    case xtream   = "Xtream Codes"
    case enigma2  = "Enigma2 / E2"

    var systemImage: String {
        switch self {
        case .m3u:     return "doc.text"
        case .stalker: return "tv.and.mediabox"
        case .xtream:  return "network"
        case .enigma2: return "antenna.radiowaves.left.and.right"
        }
    }

    var isPremiumRequired: Bool {
        self == .enigma2
    }
}
