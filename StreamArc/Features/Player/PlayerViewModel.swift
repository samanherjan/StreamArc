import StreamArcCore
import Foundation
import AVKit
import Combine
import os.log
import AVFoundation
import KSPlayer

private let playerLog = Logger(subsystem: "com.samanherjan.streamarc.StreamArc", category: "PlayerVM")

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

    /// When set, the player should use KSPlayer (for MKV/unsupported containers).
    /// The PlayerView reads this to present a KSPlayer-based view instead of AVPlayer.
    private(set) var ksPlayerURL: URL?
    private(set) var ksPlayerOptions: KSOptions?

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

    // Stalker resource loader delegate — kept alive for the duration of playback
    private var stalkerLoaderDelegate: StalkerResourceLoaderDelegate?
    private let stalkerLoaderQueue = DispatchQueue(label: "com.samanherjan.streamarc.stalkerLoader")

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
        playerLog.debug("configureSource — sourceType=\(profile.sourceType.rawValue, privacy: .public) portal=\(profile.portalURL ?? "nil", privacy: .public) mac=\(profile.macAddress ?? "nil", privacy: .public)")
        print("🔵 [PlayerVM] configureSource sourceType=\(profile.sourceType.rawValue) mac=\(profile.macAddress ?? "nil")")
        if profile.sourceType == .stalker,
           let portal = profile.portalURL,
           let mac = profile.macAddress {
            stalkerConfig = StalkerClient.Config(portalURL: portal, macAddress: mac)
        } else {
            stalkerConfig = nil
        }
    }

    private func startPlayback(url: URL) async {
        let stType = sourceType.rawValue
        let hasConfig = stalkerConfig != nil ? "set" : "nil"
        let rawURLStr = String(url.absoluteString.prefix(200))
        playerLog.debug("▶︎ startPlayback sourceType=\(stType, privacy: .public) stalkerConfig=\(hasConfig, privacy: .public) rawURL=\(rawURLStr, privacy: .public)")
        print("🔵 [PlayerVM] startPlayback sourceType=\(stType) stalkerConfig=\(hasConfig) url=\(rawURLStr)")
        do {
            let resolvedURL = try await StreamResolver.resolve(
                urlString: url.absoluteString,
                sourceType: sourceType,
                stalkerConfig: stalkerConfig
            )
            let resolvedStr = String(resolvedURL.absoluteString.prefix(200))
            playerLog.debug("✅ resolvedURL=\(resolvedStr, privacy: .public)")
            print("✅ [PlayerVM] resolvedURL=\(resolvedStr)")

            // Activate audio session before creating AVPlayer (iOS/tvOS only).
            // Without .playback category, audio is silenced in ring-silent mode
            // and AVPlayer may refuse to start on some iOS versions.
#if !os(macOS)
            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playback, mode: .moviePlayback, options: [])
                try session.setActive(true)
            } catch {
                playerLog.warning("AVAudioSession setup failed: \(error.localizedDescription, privacy: .public)")
            }
#endif

            // ── Format detection ─────────────────────────────────────────────
            // For Stalker streams we skip the byte-probe entirely. Stalker portals
            // issue single-use play_tokens: the Range request from the probe
            // validates and consumes the token, so AVFoundation's subsequent GET
            // receives the same (now-invalid) token, the server returns an HTML
            // error page, and AVFoundation fails with -11828.
            // For non-Stalker streams the probe is safe and accurate.
            let detectedMIME: String?
            if sourceType == .stalker {
                detectedMIME = nil  // fall through to URL-pattern hint below
                playerLog.debug("🔍 Stalker stream — skipping byte probe to preserve single-use play_token")
                print("🔍 [PlayerVM] Stalker stream — skipping byte probe (single-use play_token)")
            } else {
                detectedMIME = await detectMIMEType(from: resolvedURL)
                playerLog.debug("🔍 stream format: \(detectedMIME ?? "unknown — falling back to URL hint", privacy: .public)")
                print("🔍 [PlayerVM] stream format detected: \(detectedMIME ?? "nil — falling back to URL hint")")
            }

            let urlStr = resolvedURL.absoluteString
            let mimeHint: String?
            if let detected = detectedMIME {
                mimeHint = detected
            } else if urlStr.contains(".mkv") || urlStr.contains("matroska") {
                mimeHint = "video/x-matroska"
            } else if urlStr.contains(".mp4") || urlStr.contains(".m4v") {
                mimeHint = "video/mp4"
            } else if urlStr.contains(".ts") {
                mimeHint = "video/mp2t"
            } else {
                mimeHint = nil
            }

            // Use AVURLAsset with preferPreciseDurationAndTiming=false so
            // AVFoundation doesn't seek to end-of-file to compute duration —
            // critical for large MKV/TS HTTP streams (2+ GB).
            var assetOptions: [String: Any] = [
                AVURLAssetPreferPreciseDurationAndTimingKey: false
            ]
            // Don't override MIME for Stalker VOD — the redirect target's actual
            // content type may differ from what the initial URL path suggests.
            if let hint = mimeHint, !(sourceType == .stalker && allChannels.isEmpty) {
                if #available(iOS 17.0, tvOS 17.0, macOS 14.0, watchOS 10.0, *) {
                    assetOptions[AVURLAssetOverrideMIMETypeKey] = hint
                    playerLog.debug("🎯 AVURLAsset MIME override: \(hint, privacy: .public)")
                    print("🎯 [PlayerVM] AVURLAsset MIME override: \(hint)")
                }
            }

            // ── Asset creation ───────────────────────────────────────────────
            let asset: AVURLAsset
            let isLiveTV = !allChannels.isEmpty

            if sourceType == .stalker, let config = stalkerConfig, isLiveTV {
                // Stalker LIVE TV: use KSPlayer with MAG User-Agent + cookies.
                // AVFoundation's resource loader with dataTask buffers infinitely for live streams.
                // KSPlayer (FFmpeg-based) handles live TS streams natively with custom headers.
                let options = KSOptions()
                options.userAgent = config.magUserAgent
                options.appendHeader(["Cookie": config.stalkerCookie])
                // Live stream optimizations
                options.formatContextOptions["reconnect"] = 1
                options.formatContextOptions["reconnect_streamed"] = 1

                self.ksPlayerURL = resolvedURL
                self.ksPlayerOptions = options
                self.isLoading = false
                self.isPlaying = true
                playerLog.debug("🎬 Stalker Live TV (KSPlayer): \(resolvedURL.absoluteString.prefix(150), privacy: .public)")
                return  // KSPlayer handles playback

            } else if sourceType == .stalker, let config = stalkerConfig {
                // Stalker VOD: MKV container — AVFoundation cannot play MKV on tvOS.
                // Use KSPlayer (FFmpeg-based) which handles MKV natively.
                // Resolve the redirect to get the CDN URL, then hand off to KSPlayer.
                let finalURL = await resolveStalkerRedirect(url: resolvedURL, config: config)
                playerLog.debug("🎬 Stalker VOD (KSPlayer): \(finalURL.absoluteString.prefix(150), privacy: .public)")

                // Configure KSPlayer options
                let options = KSOptions()

                self.ksPlayerURL = finalURL
                self.ksPlayerOptions = options
                self.isLoading = false
                self.isPlaying = true
                return  // KSPlayer handles playback — don't create AVPlayer

            } else {
                asset = AVURLAsset(url: resolvedURL, options: assetOptions)
            }
            let item = AVPlayerItem(asset: asset)

            let avPlayer = AVPlayer(playerItem: item)
            avPlayer.automaticallyWaitsToMinimizeStalling = true
            self.player = avPlayer

            observeStatus(item: item)
            observeStalls(item: item)
            observeTime(avPlayer: avPlayer)

#if os(tvOS)
            // On tvOS, play() is deferred to AVPlayerViewControllerRepresentable
            // .updateUIViewController, which fires after the VC has been given its
            // real frame. Calling play() here (at zero-size layout) triggers
            // FigApplicationStateMonitor -19431 and -11828. isPlaying is set to
            // true by the onPlayerReady callback in the VC representable.
            _ = avPlayer  // player is set above; playback starts via VC representable
#else
            avPlayer.play()
            isPlaying = true
#endif
        } catch {
            self.isLoading = false
            self.error = "Failed to load stream: \(error.localizedDescription)"
            playerLog.error("❌ startPlayback error: \(error.localizedDescription, privacy: .public)")
            print("❌ [PlayerVM] startPlayback error: \(error)")
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

    /// Called by the tvOS AVPlayerViewControllerRepresentable once the player is attached and playing.
    func markPlaying() {
        isPlaying = true
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

    /// Exposes error setting for pre-setup validation (e.g. invalid URL before AVPlayer is created).
    func setError(_ message: String) {
        isLoading = false
        error = message
    }

    // MARK: - Stalker cookie injection

    /// Follows the HTTP redirect chain for a Stalker VOD URL (movie.php?play_token=X)
    /// with proper MAG headers to get the final direct media URL.
    /// The final URL (on the actual file/CDN server) typically doesn't need special headers,
    /// so AVFoundation can play it directly without a resource loader.
    private func resolveStalkerRedirect(url: URL, config: StalkerClient.Config) async -> URL {
        // Use a session that does NOT follow redirects automatically
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 15
        let noRedirectDelegate = NoRedirectDelegate()
        let tempSession = URLSession(configuration: sessionConfig, delegate: noRedirectDelegate, delegateQueue: nil)

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(config.magUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(config.stalkerCookie, forHTTPHeaderField: "Cookie")

        do {
            let (_, response) = try await tempSession.data(for: request)
            if let httpResponse = response as? HTTPURLResponse,
               (301...302).contains(httpResponse.statusCode),
               let location = httpResponse.value(forHTTPHeaderField: "Location"),
               let redirectURL = URL(string: location) {
                playerLog.debug("🔄 Stalker redirect resolved: \(redirectURL.absoluteString.prefix(150), privacy: .public)")
                return redirectURL
            }
            // No redirect — the URL itself serves the content directly
            // (some portals stream directly without redirect)
            playerLog.debug("🔄 No redirect — using original URL")
            return url
        } catch {
            playerLog.warning("⚠️ Redirect resolution failed: \(error.localizedDescription, privacy: .public) — using original URL")
            return url
        }
    }

    /// Injects the Stalker MAC/session cookies into HTTPCookieStorage.shared so that
    /// AVFoundation's internal URLSession includes them when fetching stream URLs.
    /// The Stalker server validates the `mac` cookie on EVERY HTTP request — including
    /// the actual stream fetch. Without these cookies AVFoundation receives an HTML
    /// error response instead of the video stream, causing -11828 (format not recognized).
    private func injectStalkerCookies(macAddress: String, host: String) {
        // Percent-encode the MAC address to match what StalkerClient sends in Cookie headers
        // (e.g. 00%3A1A%3A79%3AF6%3A7E%3A02) so the server sees a consistent value.
        let encodedMAC = macAddress
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? macAddress
        let pairs: [(String, String)] = [
            ("mac",      encodedMAC),
            ("stb_lang", "en"),
            ("timezone", "UTC"),
        ]
        for (name, value) in pairs {
            if let cookie = HTTPCookie(properties: [
                .name:    name,
                .value:   value,
                .domain:  host,
                .path:    "/",
                .version: "0",
            ]) {
                HTTPCookieStorage.shared.setCookie(cookie)
            }
        }
        playerLog.debug("🍪 Stalker cookies injected for host=\(host, privacy: .public) mac=\(macAddress, privacy: .public)")
        print("🍪 [PlayerVM] Stalker cookies injected for host=\(host) mac=\(macAddress)")
    }

    // MARK: - Cleanup

    /// Fetches the first 8 bytes of a stream URL via an HTTP Range request and
    /// returns the MIME type based on container magic bytes.
    /// Returns nil if the probe fails — callers fall back to URL-pattern heuristics.
    private func detectMIMEType(from url: URL) async -> String? {
        var request = URLRequest(url: url, timeoutInterval: 5)
        request.setValue("bytes=0-7", forHTTPHeaderField: "Range")

        guard let (data, _) = try? await URLSession.shared.data(for: request),
              data.count >= 4 else {
            playerLog.warning("⚠️ MIME probe: no data returned")
            return nil
        }

        let b = [UInt8](data)
        let hex = b.prefix(8).map { String(format: "%02X", $0) }.joined(separator: " ")
        playerLog.debug("🔬 MIME probe bytes: \(hex, privacy: .public)")
        print("🔬 [PlayerVM] MIME probe bytes: \(hex)")

        // MKV / WebM — EBML magic
        if b[0] == 0x1A && b[1] == 0x45 && b[2] == 0xDF && b[3] == 0xA3 { return "video/x-matroska" }
        // MPEG-TS — sync byte
        if b[0] == 0x47 { return "video/mp2t" }
        // MP4 / MOV — ISO Base Media box type at bytes 4-7
        if data.count >= 8 {
            let boxType = String(bytes: [b[4], b[5], b[6], b[7]], encoding: .ascii) ?? ""
            if ["ftyp", "moov", "mdat", "wide", "free", "skip"].contains(boxType) { return "video/mp4" }
        }
        // AVI — RIFF header
        if b[0] == 0x52 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x46 { return "video/x-msvideo" }
        // Raw H.264 Annex B start code — usually wrapped in TS
        if b[0] == 0x00 && b[1] == 0x00 && b[2] == 0x00 && b[3] == 0x01 { return "video/mp2t" }

        playerLog.warning("⚠️ MIME probe: unrecognised magic bytes \(hex, privacy: .public)")
        return nil
    }

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
        stalkerLoaderDelegate = nil
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
                    let avError = item.error?.localizedDescription ?? "unknown"
                    let avCode = (item.error as? NSError).map { "(\($0.domain) \($0.code))" } ?? ""
                    playerLog.error("❌ AVPlayerItem FAILED: \(avError) \(avCode)")
                    print("❌ [PlayerVM] AVPlayerItem FAILED: \(avError) \(avCode)")
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
                        let nsErr = item.error as? NSError
                        let detail = nsErr.map { " [\($0.domain) \($0.code)]" } ?? ""
                        self.error = (item.error?.localizedDescription ?? "Playback failed. The stream may be offline or unsupported.") + detail
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

/// URLSession delegate that prevents automatic redirect following,
/// allowing us to capture the Location header from 301/302 responses.
private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        // Return nil to stop following the redirect — we want the 302 response itself
        completionHandler(nil)
    }
}
