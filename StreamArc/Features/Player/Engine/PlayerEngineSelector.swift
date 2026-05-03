import Foundation
import StreamArcCore

// MARK: - PlayerEngineSelector
//
// Returns an ordered list of engines for a given URL and platform.
// The first engine is the primary; subsequent engines are tried on failure.
// Engine order: primary → fallback(s)
//
// Matrix:
//   tvOS           : KSPlayer only
//   iOS  (HLS/live): KSPlayer → VLC → (MPV stub)
//   iOS  (RTSP)    : VLC → KSPlayer
//   iOS  (rare fmt): KSPlayer → VLC → (MPV stub)
//   macOS          : KSPlayer → (MPV stub)

@MainActor
enum PlayerEngineSelector {

    /// Returns an ordered array of engines ready for the given URL.
    /// The caller should try engines in order, advancing on failure.
    static func engines(
        for url: URL,
        isLiveTV: Bool,
        sourceType: SourceType
    ) -> [any PlayerEngine] {

        let urlString = url.absoluteString.lowercased()

        // tvOS: KSPlayer is the only supported engine
#if os(tvOS)
        return [KSPlayerEngine()]

        // iOS
#elseif os(iOS)
        let ks  = KSPlayerEngine()
        let mpv = MPVPlayerEngine()
#if canImport(MobileVLCKit)
        let vlc = VLCPlayerEngine()
#endif

        // RTSP streams: VLC is best-in-class
        if urlString.hasPrefix("rtsp://") || urlString.hasPrefix("rtsps://") {
#if canImport(MobileVLCKit)
            return [vlc, ks, mpv]
#else
            return [ks, mpv]
#endif
        }

        // Stalker/MAG streams: VLC first — KSPlayer's FFmpeg backend can hard-crash
        // on certain MAG token URLs before it has a chance to report an error,
        // which prevents the engine fallback from triggering.
        if sourceType == .stalker {
#if canImport(MobileVLCKit)
            return [vlc, ks, mpv]
#else
            return [ks, mpv]
#endif
        }

        // Other live IPTV: KSPlayer first (tuned for IPTV)
        if isLiveTV {
#if canImport(MobileVLCKit)
            return [ks, vlc, mpv]
#else
            return [ks, mpv]
#endif
        }

        // Rare containers: AVI, MKV, etc. — MPV handles them best once enabled
        if urlString.hasSuffix(".avi") || urlString.hasSuffix(".mkv") ||
           urlString.hasSuffix(".flv") || urlString.hasSuffix(".wmv") {
#if canImport(MobileVLCKit)
            return [mpv, ks, vlc]
#else
            return [mpv, ks]
#endif
        }

        // Default
#if canImport(MobileVLCKit)
        return [ks, vlc, mpv]
#else
        return [ks, mpv]
#endif

        // macOS
#else
        let ks  = KSPlayerEngine()
        let mpv = MPVPlayerEngine()

        if urlString.hasSuffix(".avi") || urlString.hasSuffix(".mkv") ||
           urlString.hasSuffix(".flv") || urlString.hasSuffix(".wmv") {
            return [mpv, ks]
        }
        return [ks, mpv]
#endif
    }
}
