import StreamArcCore
import SwiftUI
import AVKit
import SwiftData
import KSPlayer

struct PlayerView: View {

    let streamURL: String
    var title: String = ""
    var isLiveTV: Bool = false
    var channel: Channel? = nil
    var allChannels: [Channel] = []
    /// Resume position in seconds; 0 = start from beginning.
    var startPosition: Double = 0
    /// Pass the active profile directly to eliminate the @Query race condition.
    /// When provided this is used instead of the internal @Query result.
    var profile: Profile? = nil

    @StateObject private var viewModel = PlayerViewModelBridge()
    @Environment(\.dismiss) private var dismiss
    @Environment(EntitlementManager.self) private var entitlements
    @Environment(\.modelContext) private var modelContext

    @Query(filter: #Predicate<Profile> { $0.isActive == true })
    private var activeProfiles: [Profile]
    private var activeProfile: Profile? { activeProfiles.first }

    @State private var showControls = true
    @State private var controlsTimer: Task<Void, Never>?
    @State private var showTrackPicker = false
    @State private var showTVOverlay = false
    @State private var tvOverlayTimer: Task<Void, Never>?

    var body: some View {
#if os(tvOS)
        tvPlayerBody
#else
        nonTVPlayerBody
#endif
    }

    // MARK: - tvOS: Native AVPlayerViewController (Siri Remote, scrubbing, transport)

#if os(tvOS)
    private var tvPlayerBody: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.06, green: 0.04, blue: 0.22), Color(red: 0.18, green: 0.10, blue: 0.38), Color(red: 0.06, green: 0.04, blue: 0.22)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            if let ksURL = viewModel.vm.ksPlayerURL {
                // KSPlayer for Stalker streams — raw video view, no built-in controls.
                // Siri Remote handles play/pause, channel switch via onMoveCommand.
                KSVideoPlayer(coordinator: viewModel.ksCoordinator, url: ksURL, options: viewModel.vm.ksPlayerOptions ?? KSOptions())
                    .onStateChanged { _, state in
                        if state == .bufferFinished {
                            viewModel.vm.markPlaying()
                        }
                    }
                    .ignoresSafeArea()
            } else {
                // AVPlayer for HLS/MP4/TS (standard streams)
                AVPlayerViewControllerRepresentable(
                    player: viewModel.vm.player,
                    onPlayerReady: { viewModel.vm.markPlaying() }
                )
                .ignoresSafeArea()
            }

            if viewModel.vm.isLoading || viewModel.vm.isBuffering {
                VStack(spacing: 12) {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(2)
                    if viewModel.vm.isBuffering {
                        Text("Buffering…")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
            }

            if let error = viewModel.vm.error {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 60)
                    Button("Dismiss") { dismiss() }
                        .buttonStyle(.bordered)
                }
            }

            // tvOS info overlay — shows on interaction, auto-hides
            if showTVOverlay {
                VStack {
                    // Title bar
                    HStack {
                        Text(title.isEmpty ? (viewModel.vm.currentLiveChannel?.name ?? "Playing") : title)
                            .font(.headline)
                            .foregroundStyle(.white)
                        Spacer()
                        if isLiveTV, let ch = viewModel.vm.currentLiveChannel {
                            Text(ch.groupTitle ?? "")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                    .padding(.horizontal, 80)
                    .padding(.top, 60)

                    Spacer()

                    // Bottom info
                    VStack(spacing: 8) {
                        if isLiveTV {
                            if let prog = channel?.currentProgram ?? viewModel.vm.currentLiveChannel?.currentProgram {
                                Text(prog.title)
                                    .font(.title3.weight(.medium))
                                    .foregroundStyle(.white)
                            }
                            Text("▲ ▼ to switch channels")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.5))
                        } else {
                            // VOD progress
                            let time = viewModel.ksCoordinator.timemodel
                            HStack {
                                Text(formatTimeTv(time.currentTime))
                                Spacer()
                                Text(formatTimeTv(time.totalTime))
                            }
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                            .padding(.horizontal, 80)

                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.white.opacity(0.3)).frame(height: 4)
                                    Capsule().fill(Color.saAccent)
                                        .frame(width: geo.size.width * progress(current: time.currentTime, total: time.totalTime), height: 4)
                                }
                            }
                            .frame(height: 4)
                            .padding(.horizontal, 80)
                        }
                    }
                    .padding(.bottom, 80)
                }
                .background(
                    LinearGradient(stops: [
                        .init(color: .black.opacity(0.7), location: 0),
                        .init(color: .clear, location: 0.3),
                        .init(color: .clear, location: 0.7),
                        .init(color: .black.opacity(0.7), location: 1),
                    ], startPoint: .top, endPoint: .bottom)
                )
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: showTVOverlay)
        .task { load() }
        .onDisappear { saveWatchProgress(); viewModel.vm.cleanup() }
        .onPlayPauseCommand {
            showTVOverlayBriefly()
            if let layer = viewModel.ksCoordinator.playerLayer {
                if layer.state == .bufferFinished {
                    layer.pause()
                } else {
                    layer.play()
                }
            } else {
                viewModel.vm.togglePlayPause()
            }
        }
        .onExitCommand {
            if showTVOverlay {
                showTVOverlay = false
            } else {
                dismiss()
            }
        }
        .onMoveCommand { direction in
            showTVOverlayBriefly()
            switch direction {
            case .up:    viewModel.vm.previousChannel()
            case .down:  viewModel.vm.nextChannel()
            case .left:  viewModel.ksCoordinator.skip(interval: -15)
            case .right: viewModel.ksCoordinator.skip(interval: 15)
            @unknown default: break
            }
        }
    }

    private func showTVOverlayBriefly() {
        showTVOverlay = true
        tvOverlayTimer?.cancel()
        tvOverlayTimer = Task {
            try? await Task.sleep(for: .seconds(5))
            if !Task.isCancelled {
                showTVOverlay = false
            }
        }
    }

    private func formatTimeTv(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }

    private func progress(current: Int, total: Int) -> CGFloat {
        guard total > 0 else { return 0 }
        return CGFloat(current) / CGFloat(total)
    }
#endif

    // MARK: - iOS / macOS: Custom overlay

#if !os(tvOS)
    private var nonTVPlayerBody: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.06, green: 0.04, blue: 0.22), Color(red: 0.18, green: 0.10, blue: 0.38), Color(red: 0.06, green: 0.04, blue: 0.22)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            if let ksURL = viewModel.vm.ksPlayerURL {
                // KSPlayer for Stalker streams — raw video view, custom controls below
                KSVideoPlayer(coordinator: viewModel.ksCoordinator, url: ksURL, options: viewModel.vm.ksPlayerOptions ?? KSOptions())
                    .onStateChanged { _, state in
                        if state == .bufferFinished {
                            viewModel.vm.markPlaying()
                        }
                    }
                    .ignoresSafeArea()
                    .onTapGesture { toggleControls() }
            } else if let player = viewModel.vm.player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
                    .onTapGesture { toggleControls() }
            }

            if viewModel.vm.isLoading || viewModel.vm.isBuffering {
                VStack(spacing: 12) {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(2)
                    if viewModel.vm.isBuffering {
                        Text("Buffering…")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
            }

            if let error = viewModel.vm.error {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.red)
                    Text(error)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    Button("Retry") { load() }
                        .buttonStyle(.bordered)
                        .tint(.white)
                }
            }

            if showControls {
                playerControls
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showControls)
#if os(iOS)
        .statusBarHidden(true)
#endif
        .task { load() }
        .onDisappear { saveWatchProgress(); viewModel.vm.cleanup() }
    }

    // MARK: - Controls

    private var playerControls: some View {
        VStack {
            // Top bar
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                }
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer()

                // Track picker (audio/subtitles)
                Button {
                    showTrackPicker = true
                    controlsTimer?.cancel()
                } label: {
                    Image(systemName: "waveform")
                        .font(.title3)
                        .foregroundStyle(.white)
                }

                // AirPlay
                AirPlayButton()
                    .frame(width: 44, height: 44)

                // PiP
                if entitlements.isPremium {
                    Button {
                        viewModel.vm.togglePiP(isPremium: entitlements.isPremium)
                    } label: {
                        Image(systemName: viewModel.vm.isPIPActive ? "pip.exit" : "pip.enter")
                            .font(.title3)
                            .foregroundStyle(.white)
                    }
                }
            }
            .padding()
            .background(.ultraThinMaterial.opacity(0.7))

            Spacer()

            // EPG info strip (live TV only)
            if isLiveTV, let prog = channel?.currentProgram ?? viewModel.vm.currentLiveChannel?.currentProgram {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(prog.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        if let desc = prog.description, !desc.isEmpty {
                            Text(desc)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.7))
                                .lineLimit(2)
                        }
                    }
                    Spacer()
                    // Program progress
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(timeRangeString(start: prog.startDate, end: prog.endDate))
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.7))
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.3)).frame(height: 3)
                                Capsule().fill(Color.saAccent)
                                    .frame(width: geo.size.width * prog.progress, height: 3)
                            }
                        }
                        .frame(width: 80, height: 3)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial.opacity(0.5))
            }

            // Bottom controls
            VStack(spacing: 12) {
                if !isLiveTV && viewModel.vm.duration > 0 {
                    VStack(spacing: 4) {
                        Slider(
                            value: Binding(get: { viewModel.vm.currentTime }, set: { viewModel.vm.seek(to: $0) }),
                            in: 0...max(1, viewModel.vm.duration)
                        )
                        .tint(Color.saAccent)
                        .padding(.horizontal)
                        HStack {
                            Text(formatTime(viewModel.vm.currentTime))
                            Spacer()
                            Text(formatTime(viewModel.vm.duration))
                        }
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.6))
                        .padding(.horizontal)
                    }
                }

                HStack(spacing: 32) {
                    if isLiveTV {
                        Button { viewModel.vm.previousChannel() } label: {
                            Image(systemName: "chevron.up.circle.fill").font(.title).foregroundStyle(.white)
                        }
                    } else {
                        Button { viewModel.vm.seekRelative(-15) } label: {
                            Image(systemName: "gobackward.15").font(.title).foregroundStyle(.white)
                        }
                    }

                    Button { viewModel.vm.togglePlayPause() } label: {
                        Image(systemName: viewModel.vm.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 52))
                            .foregroundStyle(.white)
                    }

                    if isLiveTV {
                        Button { viewModel.vm.nextChannel() } label: {
                            Image(systemName: "chevron.down.circle.fill").font(.title).foregroundStyle(.white)
                        }
                    } else {
                        Button { viewModel.vm.seekRelative(30) } label: {
                            Image(systemName: "goforward.30").font(.title).foregroundStyle(.white)
                        }
                    }
                }
            }
            .padding()
            .background(.ultraThinMaterial.opacity(0.7))
        }
        .sheet(isPresented: $showTrackPicker) {
            TrackPickerSheet(playerVM: viewModel.vm) {
                showTrackPicker = false
                scheduleHideControls()
            }
        }
    }

    private func timeRangeString(start: Date, end: Date) -> String {
        let f = DateFormatter()
        f.timeStyle = .short
        return "\(f.string(from: start)) – \(f.string(from: end))"
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        let s = Int(seconds)
        let m = s / 60
        let h = m / 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m % 60, s % 60)
        }
        return String(format: "%d:%02d", m, s % 60)
    }
#endif

    // MARK: - Helpers

    private func load() {
        guard !streamURL.isEmpty else {
            viewModel.vm.setError("No stream URL provided.")
            return
        }

        let sanitized = streamURL.trimmingCharacters(in: .whitespacesAndNewlines)

        // Construct URL — for Stalker VOD base64 cmds that aren't valid URLs,
        // use percent-encoding fallback. StreamResolver.resolve() receives
        // url.absoluteString and handles all formats (http URLs, base64 blobs, etc.)
        guard let url = URL(string: sanitized) ??
              URL(string: sanitized.addingPercentEncoding(
                withAllowedCharacters: .urlQueryAllowed
                    .union(.urlHostAllowed)
                    .union(.urlPathAllowed)) ?? sanitized)
        else {
            viewModel.vm.setError("Invalid stream URL.")
            return
        }

        // Use the directly-passed profile first; fall back to @Query result.
        if let resolvedProfile = profile ?? activeProfile {
            viewModel.vm.configureSource(profile: resolvedProfile)
        }
        let idx = allChannels.firstIndex(where: { $0.streamURL == streamURL }) ?? 0
        viewModel.vm.pendingSeekPosition = startPosition
        viewModel.vm.setup(url: url, channels: allChannels, currentIndex: idx)
        scheduleHideControls()
    }

    private func saveWatchProgress() {
        guard !isLiveTV else { return }
        let contentId = channel?.id ?? streamURL
        let mgr = WatchHistoryManager(modelContext: modelContext)
        try? mgr.record(
            contentId: contentId,
            contentType: isLiveTV ? "channel" : "vod",
            title: title,
            imageURL: nil,
            position: viewModel.vm.currentTime,
            duration: viewModel.vm.duration
        )
    }

    private func toggleControls() {
        withAnimation { showControls.toggle() }
        if showControls { scheduleHideControls() }
    }

    private func scheduleHideControls() {
        controlsTimer?.cancel()
        controlsTimer = Task {
            try? await Task.sleep(for: .seconds(4))
            if !Task.isCancelled {
                withAnimation { showControls = false }
            }
        }
    }
}

// Bridge to use @StateObject with @Observable PlayerViewModel
@MainActor
final class PlayerViewModelBridge: ObservableObject {
    let vm = PlayerViewModel()
    let ksCoordinator = KSVideoPlayer.Coordinator()
}

// MARK: - tvOS AVPlayerViewController wrapper

#if os(tvOS)
struct AVPlayerViewControllerRepresentable: UIViewControllerRepresentable {
    /// The player to attach. nil renders a blank VC (before playback begins).
    let player: AVPlayer?
    /// Called once when the player has been attached to the VC post-layout and play() triggered.
    var onPlayerReady: (() -> Void)?

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        // ⚠️ Do NOT set vc.player here.
        // makeUIViewController is called during the initial SwiftUI layout pass
        // when UIKit has not yet given the VC a real frame (it gets a temporary
        // zero-width constraint: _UITemporaryLayoutWidth = 0). On tvOS the media
        // server (FigApplicationStateMonitor) refuses to initialise the pipeline
        // against a zero-size surface and the AVPlayerItem immediately fails with
        // AVFoundationErrorDomain -11828. The player is assigned in
        // updateUIViewController, which fires after the view hierarchy is settled
        // and the VC has its full-screen frame.
        vc.showsPlaybackControls = true
        vc.allowsPictureInPicturePlayback = false
        return vc
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        guard let player else {
            if uiViewController.player != nil { uiViewController.player = nil }
            return
        }
        guard uiViewController.player !== player else { return }
        // Assign the player now that the VC has its real frame.
        uiViewController.player = player
        // Start playback. The player's AVPlayerItem may still be loading, but
        // calling play() here queues it so playback begins as soon as readyToPlay.
        if player.rate == 0 { player.play() }
        onPlayerReady?()
    }
}
#endif

// MARK: - Track Picker Sheet (Audio & Subtitles)

#if !os(tvOS)
struct TrackPickerSheet: View {
    let playerVM: PlayerViewModel
    var onDismiss: () -> Void

    @State private var audioOptions: [AVMediaSelectionOption] = []
    @State private var subtitleOptions: [AVMediaSelectionOption] = []

    var body: some View {
        NavigationStack {
            List {
                if !audioOptions.isEmpty {
                    Section("Audio") {
                        ForEach(audioOptions, id: \.displayName) { option in
                            Button {
                                Task { await playerVM.selectAudioOption(option) }
                                onDismiss()
                            } label: {
                                HStack {
                                    Text(option.displayName)
                                        .foregroundStyle(Color.saTextPrimary)
                                    Spacer()
                                    if let lang = option.extendedLanguageTag {
                                        Text(lang.uppercased())
                                            .font(.caption)
                                            .foregroundStyle(Color.saTextSecondary)
                                    }
                                }
                            }
                        }
                    }
                }

                if !subtitleOptions.isEmpty {
                    Section("Subtitles") {
                        ForEach(subtitleOptions, id: \.displayName) { option in
                            Button {
                                Task { await playerVM.selectSubtitleOption(option) }
                                onDismiss()
                            } label: {
                                HStack {
                                    Text(option.displayName)
                                        .foregroundStyle(Color.saTextPrimary)
                                    Spacer()
                                    if let lang = option.extendedLanguageTag {
                                        Text(lang.uppercased())
                                            .font(.caption)
                                            .foregroundStyle(Color.saTextSecondary)
                                    }
                                }
                            }
                        }
                    }
                }

                if audioOptions.isEmpty && subtitleOptions.isEmpty {
                    Section {
                        Text("No alternate audio or subtitle tracks available for this stream.")
                            .font(.subheadline)
                            .foregroundStyle(Color.saTextSecondary)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.saBackground)
            .navigationTitle("Audio & Subtitles")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDismiss)
                }
            }
        }
        .presentationDetents([.medium])
        .task {
            audioOptions = await playerVM.availableAudioOptions()
            subtitleOptions = await playerVM.availableSubtitleOptions()
        }
    }
}
#endif

// MARK: - AirPlay button

#if os(iOS)
struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let v = AVRoutePickerView()
        v.tintColor = .white
        v.activeTintColor = UIColor(Color.saAccent)
        return v
    }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
#elseif os(macOS)
struct AirPlayButton: NSViewRepresentable {
    func makeNSView(context: Context) -> AVRoutePickerView {
        let v = AVRoutePickerView()
        v.isRoutePickerButtonBordered = false
        return v
    }
    func updateNSView(_ nsView: AVRoutePickerView, context: Context) {}
}
#endif
