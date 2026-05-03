// VLCPlayerEngine.swift
// Wraps MobileVLCKit (iOS) as a PlayerEngine backend.
// VLCKit uses libvlc — no FFmpeg symbol conflict with KSPlayer.
// Available on iOS only (the local MobileVLCKit package only contains iOS slices).

#if canImport(MobileVLCKit)
import SwiftUI
import MobileVLCKit

// MARK: - VLC PlayerEngine

@MainActor
final class VLCPlayerEngine: NSObject, PlayerEngine {

    let engineType: PlayerEngineType = .vlc

    private(set) var engineState: PlayerEngineState = .idle
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0

    var onStateChanged: (@MainActor (PlayerEngineState) -> Void)?
    var onTimeUpdate: (@MainActor (Double, Double) -> Void)?

    // MARK: Internals

    private let player = VLCMediaPlayer()
    private var timeTask: Task<Void, Never>?

    override init() {
        super.init()
        player.delegate = self
    }

    // MARK: - PlayerEngine

    func load(url: URL, options: PlayerEngineOptions) {
        teardown()

        let media = VLCMedia(url: url)

        // Inject headers / user-agent as VLC options
        if let ua = options.userAgent {
            media.addOption("--http-user-agent=\(ua)")
        }
        for (key, value) in options.headers {
            media.addOption("--http-header-fields=\(key): \(value)")
        }
        if options.isLiveTV {
            // Live-TV: reduce caching to minimise delay
            media.addOption(":network-caching=1000")
            media.addOption(":live-caching=1000")
        }

        player.media = media
        player.play()

        transition(to: .loading)
        startTimePolling()
    }

    func play() {
        player.play()
        if engineState == .paused { transition(to: .playing) }
    }

    func pause() {
        player.pause()
        if engineState == .playing || engineState == .buffering {
            transition(to: .paused)
        }
    }

    func seek(to seconds: Double) {
        guard let media = player.media else { return }
        let total = Double(media.length.intValue) / 1000.0
        guard total > 0 else { return }
        let position = Float(max(0, min(seconds / total, 1)))
        player.position = position
    }

    func teardown() {
        timeTask?.cancel()
        timeTask = nil
        player.stop()
        transition(to: .idle)
    }

    func makePlayerView() -> AnyView {
        AnyView(VLCVideoViewRepresentable(player: player))
    }

    // MARK: - Helpers

    private func transition(to new: PlayerEngineState) {
        guard engineState != new else { return }
        engineState = new
        onStateChanged?(new)
    }

    private func startTimePolling() {
        timeTask?.cancel()
        timeTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard let self, !Task.isCancelled else { break }
                guard let media = self.player.media else { continue }
                let total = Double(media.length.intValue) / 1000.0
                let current = Double(self.player.time.intValue) / 1000.0
                self.currentTime = current
                self.duration = total
                self.onTimeUpdate?(current, total)
            }
        }
    }
}

// MARK: - VLCMediaPlayerDelegate

extension VLCPlayerEngine: VLCMediaPlayerDelegate {
    nonisolated func mediaPlayerStateChanged(_ aNotification: Notification) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let state = self.player.state
            switch state {
            case .opening, .buffering:
                self.transition(to: .buffering)
            case .playing:
                self.transition(to: .playing)
            case .paused:
                self.transition(to: .paused)
            case .stopped, .ended:
                self.transition(to: .idle)
            case .error:
                self.transition(to: .error("VLCKit encountered a playback error."))
            default:
                break
            }
        }
    }

    nonisolated func mediaPlayerTimeChanged(_ aNotification: Notification) {
        // Time is polled via the background Task — no action needed here.
    }
}

// MARK: - VLC Video Surface (UIViewRepresentable)

private struct VLCVideoViewRepresentable: UIViewRepresentable {
    let player: VLCMediaPlayer

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        player.drawable = view
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        // Drawable is set once; no update needed.
    }
}

#endif // canImport(MobileVLCKit)
