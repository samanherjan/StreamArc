import StreamArcCore
import Foundation
import AVKit
import Combine

@MainActor
@Observable
final class PlayerViewModel: NSObject {

    private(set) var player: AVPlayer?
    private(set) var isPlaying = false
    private(set) var isPIPActive = false
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0
    private(set) var isLoading = true
    private(set) var isBuffering = false
    private(set) var error: String?

    var currentChannelIndex: Int = 0
    private var allChannels: [Channel] = []
    private var timeObserver: Any?
    private var statusObservation: NSKeyValueObservation?
    private var stallObservation: NSKeyValueObservation?
    private var stalkerConfig: StalkerClient.Config?
    private var sourceType: SourceType = .m3u
    private var retryCount = 0
    private var currentURL: URL?
    private let retryPolicy = RetryPolicy(maxAttempts: 3, baseDelay: 1.0, maxDelay: 8.0)

    // Fallback URL cycling — populated from Channel.fallbackURLs on setup
    private var fallbackURLs: [String] = []
    private var fallbackIndex = 0

    // Pending seek position (seconds) applied once the player is ready (for VOD resume)
    var pendingSeekPosition: Double = 0

    /// The channel currently loaded (updated on channel switches).
    private(set) var currentLiveChannel: Channel?

#if !os(tvOS)
    private var pipController: AVPictureInPictureController?
#endif

    // MARK: - Setup

    /// Primary setup: sanitises URL, resolves Stalker streams, configures AVPlayer.
    func setup(url: URL, channels: [Channel] = [], currentIndex: Int = 0) {
        cleanup()
        allChannels = channels
        currentChannelIndex = currentIndex
        currentLiveChannel = (currentIndex < channels.count) ? channels[currentIndex] : nil
        currentLiveChannel = (currentIndex < channels.count) ? channels[currentIndex] : nil
        retryCount = 0
        fallbackIndex = 0
        fallbackURLs = (currentIndex < channels.count) ? channels[currentIndex].fallbackURLs : []
        error = nil
        isLoading = true
        isBuffering = false
        currentURL = url

        Task { @MainActor in
            await startPlayback(url: url)
        }
    }

    /// Configure the source context so the player knows how to resolve Stalker URLs.
    func configureSource(profile: Profile) {
        sourceType = profile.sourceType
        if profile.sourceType == .stalker,
           let portal = profile.portalURL,
           let mac = profile.macAddress {
            stalkerConfig = StalkerClient.Config(portalURL: portal, macAddress: mac)
        } else {
            stalkerConfig = nil
        }
    }

    private func startPlayback(url: URL) async {
        do {
            let resolvedURL = try await StreamResolver.resolve(
                urlString: url.absoluteString,
                sourceType: sourceType,
                stalkerConfig: stalkerConfig
            )
            let item = AVPlayerItem(url: resolvedURL)
            item.preferredForwardBufferDuration = 8

            let avPlayer = AVPlayer(playerItem: item)
            avPlayer.automaticallyWaitsToMinimizeStalling = true
            self.player = avPlayer

            observeStatus(item: item)
            observeStalls(item: item)
            observeTime(avPlayer: avPlayer)

            avPlayer.play()
            isPlaying = true
        } catch {
            self.isLoading = false
            self.error = "Failed to load stream: \(error.localizedDescription)"
        }
    }

    // MARK: - Playback controls

    func togglePlayPause() {
        guard let player else { return }
        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
        isPlaying.toggle()
    }

    func seek(to seconds: Double) {
        player?.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
    }

    func seekRelative(_ delta: Double) {
        let target = max(0, currentTime + delta)
        seek(to: target)
    }

    // MARK: - Channel switching (Live TV)

    func nextChannel() {
        guard !allChannels.isEmpty else { return }
        currentChannelIndex = (currentChannelIndex + 1) % allChannels.count
        switchToChannel(at: currentChannelIndex)
    }

    func previousChannel() {
        guard !allChannels.isEmpty else { return }
        currentChannelIndex = (currentChannelIndex - 1 + allChannels.count) % allChannels.count
        switchToChannel(at: currentChannelIndex)
    }

    private func switchToChannel(at index: Int) {
        guard index < allChannels.count else { return }
        let channel = allChannels[index]
        currentLiveChannel = channel
        guard let url = URL(string: channel.streamURL) else { return }
        setup(url: url, channels: allChannels, currentIndex: index)
    }

    // MARK: - PiP (premium)

    func setupPiP(playerLayer: AVPlayerLayer, isPremium: Bool) {
#if !os(tvOS)
        guard isPremium, AVPictureInPictureController.isPictureInPictureSupported() else { return }
        let pip = AVPictureInPictureController(playerLayer: playerLayer)
        pip?.delegate = self
        pipController = pip
#endif
    }

    func togglePiP(isPremium: Bool) {
#if !os(tvOS)
        guard isPremium else { return }
        if isPIPActive {
            pipController?.stopPictureInPicture()
        } else {
            pipController?.startPictureInPicture()
        }
#endif
    }

    // MARK: - Audio / subtitle tracks

    func availableAudioOptions() async -> [AVMediaSelectionOption] {
        guard let group = try? await player?.currentItem?.asset.loadMediaSelectionGroup(for: .audible) else {
            return []
        }
        return group.options
    }

    func selectAudioOption(_ option: AVMediaSelectionOption) async {
        guard let item = player?.currentItem,
              let group = try? await item.asset.loadMediaSelectionGroup(for: .audible) else { return }
        item.select(option, in: group)
    }

    func availableSubtitleOptions() async -> [AVMediaSelectionOption] {
        guard let group = try? await player?.currentItem?.asset.loadMediaSelectionGroup(for: .legible) else {
            return []
        }
        return group.options
    }

    func selectSubtitleOption(_ option: AVMediaSelectionOption) async {
        guard let item = player?.currentItem,
              let group = try? await item.asset.loadMediaSelectionGroup(for: .legible) else { return }
        item.select(option, in: group)
    }

    // MARK: - Cleanup

    func cleanup() {
        statusObservation?.invalidate()
        statusObservation = nil
        stallObservation?.invalidate()
        stallObservation = nil
        if let obs = timeObserver {
            player?.removeTimeObserver(obs)
            timeObserver = nil
        }
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
        isLoading = true
        isBuffering = false
        error = nil
    }

    // MARK: - Observation (KVO — reliable across all platforms including tvOS)

    private func observeStatus(item: AVPlayerItem) {
        statusObservation?.invalidate()
        statusObservation = item.observe(\.status, options: [.new, .initial]) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch item.status {
                case .readyToPlay:
                    self.isLoading = false
                    self.isBuffering = false
                    self.error = nil
                    let dur = try? await item.asset.load(.duration)
                    if let dur, dur.seconds.isFinite {
                        self.duration = dur.seconds
                    }
                    // Resume from saved position (VOD continue-watching)
                    if self.pendingSeekPosition > 0 {
                        self.seek(to: self.pendingSeekPosition)
                        self.pendingSeekPosition = 0
                    }
                case .failed:
                    // Retry with exponential backoff first
                    if self.retryCount < self.retryPolicy.maxAttempts {
                        let attempt = self.retryCount
                        self.retryCount += 1
                        let delay = self.retryPolicy.delay(forAttempt: attempt)
                        print("[PlayerVM] Retry \(self.retryCount)/\(self.retryPolicy.maxAttempts) after \(delay)s")
                        if let url = self.currentURL {
                            try? await Task.sleep(for: .seconds(delay))
                            guard !Task.isCancelled else { return }
                            await self.startPlayback(url: url)
                        }
                    } else if self.fallbackIndex < self.fallbackURLs.count {
                        // Primary + retries exhausted — try next fallback source
                        let fallbackStr = self.fallbackURLs[self.fallbackIndex]
                        self.fallbackIndex += 1
                        self.retryCount = 0
                        print("[PlayerVM] Fallback \(self.fallbackIndex)/\(self.fallbackURLs.count): \(fallbackStr)")
                        if let fallbackURL = URL(string: fallbackStr) {
                            self.currentURL = fallbackURL
                            await self.startPlayback(url: fallbackURL)
                        }
                    } else {
                        self.isLoading = false
                        self.isBuffering = false
                        self.error = item.error?.localizedDescription ?? "Playback failed. The stream may be offline or unsupported."
                    }
                default:
                    break
                }
            }
        }
    }

    /// Monitors playback stalls and shows buffering indicator.
    private func observeStalls(item: AVPlayerItem) {
        stallObservation?.invalidate()
        stallObservation = item.observe(\.isPlaybackLikelyToKeepUp, options: [.new]) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isBuffering = !item.isPlaybackLikelyToKeepUp && self.isPlaying
            }
        }
    }

    private func observeTime(avPlayer: AVPlayer) {
        let interval = CMTime(seconds: 1, preferredTimescale: 1)
        timeObserver = avPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor in
                self?.currentTime = time.seconds
            }
        }
    }
}

#if !os(tvOS)
extension PlayerViewModel: AVPictureInPictureControllerDelegate {
    nonisolated func pictureInPictureControllerDidStartPictureInPicture(_ controller: AVPictureInPictureController) {
        Task { @MainActor in isPIPActive = true }
    }
    nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ controller: AVPictureInPictureController) {
        Task { @MainActor in isPIPActive = false }
    }
}
#endif
