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
    private(set) var error: String?

    var currentChannelIndex: Int = 0
    private var allChannels: [Channel] = []
    private var timeObserver: Any?
    private var statusObservation: NSKeyValueObservation?
    private var stalkerClient: StalkerClient?
    private var sourceType: SourceType = .m3u
    private var retryCount = 0
    private static let maxRetries = 2

#if !os(tvOS)
    private var pipController: AVPictureInPictureController?
#endif

    // MARK: - Setup

    /// Primary setup: sanitises URL, resolves Stalker streams, configures AVPlayer.
    func setup(url: URL, channels: [Channel] = [], currentIndex: Int = 0) {
        cleanup()
        allChannels = channels
        currentChannelIndex = currentIndex
        retryCount = 0
        error = nil
        isLoading = true

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
            stalkerClient = StalkerClient(config: .init(portalURL: portal, macAddress: mac))
        } else {
            stalkerClient = nil
        }
    }

    private func startPlayback(url: URL) async {
        do {
            let resolvedURL = try await resolveStreamURL(url)
            let item = AVPlayerItem(url: resolvedURL)
            item.preferredForwardBufferDuration = 5

            let avPlayer = AVPlayer(playerItem: item)
            avPlayer.automaticallyWaitsToMinimizeStalling = true
            self.player = avPlayer

            observeStatus(item: item)
            observeTime(avPlayer: avPlayer)

            avPlayer.play()
            isPlaying = true
        } catch {
            self.isLoading = false
            self.error = "Failed to load stream: \(error.localizedDescription)"
        }
    }

    /// Resolves the final playable URL. Strips "ffmpeg " prefix, resolves Stalker cmd URLs.
    private func resolveStreamURL(_ url: URL) async throws -> URL {
        var urlString = url.absoluteString

        // Strip common "ffmpeg " prefix from Stalker/portal URLs
        if urlString.hasPrefix("ffmpeg ") {
            urlString = String(urlString.dropFirst(7))
        }

        // Stalker sources need server-side link creation
        if sourceType == .stalker, let client = stalkerClient {
            do {
                try await client.authenticate()
                let resolved = try await client.resolveStreamURL(cmd: urlString)
                let clean = resolved.hasPrefix("ffmpeg ") ? String(resolved.dropFirst(7)) : resolved
                guard let finalURL = URL(string: clean) else {
                    throw URLError(.badURL)
                }
                return finalURL
            } catch {
                // If resolution fails, try the raw URL as fallback
                print("[PlayerVM] Stalker resolve failed, trying raw URL: \(error)")
            }
        }

        guard let finalURL = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        return finalURL
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

    // MARK: - Cleanup

    func cleanup() {
        statusObservation?.invalidate()
        statusObservation = nil
        if let obs = timeObserver {
            player?.removeTimeObserver(obs)
            timeObserver = nil
        }
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
        isLoading = true
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
                    self.error = nil
                    let dur = try? await item.asset.load(.duration)
                    if let dur, dur.seconds.isFinite {
                        self.duration = dur.seconds
                    }
                case .failed:
                    // Retry logic
                    if self.retryCount < Self.maxRetries {
                        self.retryCount += 1
                        print("[PlayerVM] Retry \(self.retryCount)/\(Self.maxRetries)")
                        if let url = (item.asset as? AVURLAsset)?.url {
                            try? await Task.sleep(for: .seconds(1))
                            await self.startPlayback(url: url)
                        }
                    } else {
                        self.isLoading = false
                        self.error = item.error?.localizedDescription ?? "Playback failed. The stream may be offline or unsupported."
                    }
                default:
                    break
                }
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
