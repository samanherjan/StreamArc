import SwiftUI
import KSPlayer

// MARK: - KSPlayerEngine

/// Wraps KSPlayer as a PlayerEngine backend.
/// Works on iOS, tvOS and macOS.
@MainActor
final class KSPlayerEngine: PlayerEngine {

    let engineType: PlayerEngineType = .ks

    // MARK: State

    private(set) var engineState: PlayerEngineState = .idle
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0

    var onStateChanged: (@MainActor (PlayerEngineState) -> Void)?
    var onTimeUpdate: (@MainActor (Double, Double) -> Void)?

    // MARK: Internals

    let coordinator = KSVideoPlayer.Coordinator()

    private var loadedURL: URL?
    private var loadedOptions: KSOptions?
    private var timeTask: Task<Void, Never>?

    // MARK: - PlayerEngine

    func load(url: URL, options engineOptions: PlayerEngineOptions) {
        teardown()

        let ksOptions = buildKSOptions(from: engineOptions, url: url)
        loadedURL = url
        loadedOptions = ksOptions

        transition(to: .loading)
        startTimePolling()
    }

    func play() {
        coordinator.playerLayer?.play()
        if engineState == .paused { transition(to: .playing) }
    }

    func pause() {
        coordinator.playerLayer?.pause()
        if engineState == .playing || engineState == .buffering {
            transition(to: .paused)
        }
    }

    func seek(to seconds: Double) {
        coordinator.seek(time: seconds)
    }

    func teardown() {
        timeTask?.cancel()
        timeTask = nil
        coordinator.playerLayer?.pause()
        loadedURL = nil
        loadedOptions = nil
        transition(to: .idle)
    }

    func makePlayerView() -> AnyView {
        guard let url = loadedURL, let options = loadedOptions else {
            return AnyView(Color.black.ignoresSafeArea())
        }
        // Use the engine's own coordinator so state changes (playing, error, buffering)
        // feed back into KSPlayerEngine and the polling loop gets real time data.
        return AnyView(
            KSVideoPlayerView(coordinator: coordinator, url: url, options: options)
                .ignoresSafeArea()
        )
    }

    // MARK: - Helpers

    private func handleKSState(_ state: KSPlayerState) {
        switch state {
        case .readyToPlay, .bufferFinished:
            transition(to: .playing)
        case .buffering:
            transition(to: .buffering)
        case .paused:
            if engineState != .idle { transition(to: .paused) }
        case .error:
            transition(to: .error("KSPlayer encountered a playback error."))
        default:
            break
        }
    }

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
                let model = self.coordinator.timemodel
                let ct = Double(model.currentTime)
                let dt = Double(model.totalTime)
                self.currentTime = ct
                self.duration = dt
                self.onTimeUpdate?(ct, dt)

                // Mirror coordinator state back into the engine state machine so
                // that playing / buffering / error states are properly reported.
                // This is necessary because KSVideoPlayerView sets its own
                // coordinator.onStateChanged callback that overwrites any we set.
                let ksState = self.coordinator.state
                self.syncStateFromCoordinator(ksState)
            }
        }
    }

    /// Maps the current KSPlayer coordinator state to our engine state machine.
    /// Called periodically from the time-polling loop.
    private func syncStateFromCoordinator(_ ksState: KSPlayerState) {
        switch ksState {
        case .readyToPlay, .bufferFinished:
            if engineState != .playing { transition(to: .playing) }
        case .buffering:
            if engineState != .buffering { transition(to: .buffering) }
        case .paused:
            if engineState == .playing || engineState == .buffering {
                transition(to: .paused)
            }
        case .error:
            if case .error = engineState { /* already in error */ } else {
                transition(to: .error("KSPlayer encountered a playback error."))
            }
        default:
            break
        }
    }

    /// Internal helper also used by PlayerViewModel to build the legacy `ksPlayerOptions` shim.
    func buildKSOptionsPublic(from opts: PlayerEngineOptions, url: URL) -> KSOptions {
        buildKSOptions(from: opts, url: url)
    }

    private func buildKSOptions(from opts: PlayerEngineOptions, url: URL) -> KSOptions {
        let o = KSOptions()
        if let ua = opts.userAgent { o.userAgent = ua }
        if !opts.headers.isEmpty { o.appendHeader(opts.headers) }

        let lower = url.absoluteString.lowercased()
        let isHLS = lower.contains(".m3u8")

        // Always enable the full protocol whitelist and reconnect so FFmpeg
        // can handle HTTP redirects, segmented streams, and transient network
        // errors for both live TV and on-demand (series episodes, movies, etc.)
        o.formatContextOptions["protocol_whitelist"] = "file,http,https,tcp,tls,crypto,async,cache,data,httpproxy"
        o.formatContextOptions["reconnect"] = 1
        o.formatContextOptions["reconnect_streamed"] = 1

        if opts.isLiveTV || isHLS {
            o.preferredForwardBufferDuration = opts.isLiveTV ? 1.0 : 2.0
            o.maxBufferDuration = opts.isLiveTV ? 20.0 : 30.0
        } else {
            // VOD / series episodes — allow a reasonable lookahead buffer
            o.preferredForwardBufferDuration = 4.0
            o.maxBufferDuration = 60.0
        }

        #if os(iOS)
        // On iOS/iPadOS hardware decode can sometimes produce audio-only playback
        // (video layer not attached) for certain codecs. Force software decode so
        // FFmpeg renders directly into the view layer — consistent with tvOS behaviour.
        o.hardwareDecode = false
        #endif

        return o
    }
}
