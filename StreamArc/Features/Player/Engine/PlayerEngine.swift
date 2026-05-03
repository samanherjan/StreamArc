import SwiftUI
import Foundation

// MARK: - Player Engine State

enum PlayerEngineState: Equatable, Sendable {
    case idle
    case loading
    case playing
    case paused
    case buffering
    case error(String)

    var isActive: Bool {
        switch self {
        case .playing, .buffering: return true
        default: return false
        }
    }

    var errorMessage: String? {
        if case .error(let msg) = self { return msg }
        return nil
    }
}

// MARK: - Player Engine Options

struct PlayerEngineOptions: Sendable {
    var headers: [String: String] = [:]
    var userAgent: String?
    var isLiveTV: Bool = false
    var startPosition: Double = 0

    static let `default` = PlayerEngineOptions()
}

// MARK: - Engine Type

enum PlayerEngineType: String, CaseIterable {
    case ks  = "KSPlayer"
    case vlc = "VLCKit"
    case mpv = "MPV"
}

// MARK: - PlayerEngine Protocol

/// Abstraction over KSPlayer, VLCKit and MPV backends.
/// All access must be on the @MainActor.
@MainActor
protocol PlayerEngine: AnyObject {

    var engineType: PlayerEngineType { get }
    var engineState: PlayerEngineState { get }
    var currentTime: Double { get }
    var duration: Double { get }

    /// Called whenever the engine changes state (loading, playing, buffering, error …).
    var onStateChanged: (@MainActor (PlayerEngineState) -> Void)? { get set }

    /// Called every ~0.5 s during playback with (currentTime, duration).
    var onTimeUpdate: (@MainActor (Double, Double) -> Void)? { get set }

    /// Load and begin playing the given URL.
    func load(url: URL, options: PlayerEngineOptions)

    func play()
    func pause()
    func seek(to seconds: Double)
    func teardown()

    /// Return the SwiftUI view that renders this engine's video output.
    func makePlayerView() -> AnyView
}
