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

#if !os(tvOS)
    private var pipController: AVPictureInPictureController?
#endif

    // MARK: - Setup

    func setup(url: URL, channels: [Channel] = [], currentIndex: Int = 0) {
        cleanup()
        allChannels = channels
        currentChannelIndex = currentIndex

        let item = AVPlayerItem(url: url)
        let avPlayer = AVPlayer(playerItem: item)
        self.player = avPlayer

        observeStatus(item: item)
        observeTime(avPlayer: avPlayer)

        avPlayer.play()
        isPlaying = true
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
        if let obs = timeObserver {
            player?.removeTimeObserver(obs)
            timeObserver = nil
        }
        player?.pause()
        player = nil
        isLoading = true
    }

    // MARK: - Observation

    private func observeStatus(item: AVPlayerItem) {
        Task { @MainActor [weak self] in
            for await status in item.publisher(for: \.status).values {
                switch status {
                case .readyToPlay:
                    self?.isLoading = false
                    self?.duration = item.duration.seconds.isFinite ? item.duration.seconds : 0
                case .failed:
                    self?.isLoading = false
                    self?.error = item.error?.localizedDescription ?? "Playback failed"
                default: break
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
