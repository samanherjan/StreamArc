import StreamArcCore
import SwiftUI
import AVKit
import SwiftData

struct PlayerView: View {

    let streamURL: String
    var title: String = ""
    var isLiveTV: Bool = false
    var channel: Channel? = nil
    var allChannels: [Channel] = []
    /// Resume position in seconds; 0 = start from beginning.
    var startPosition: Double = 0

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
            Color.black.ignoresSafeArea()

            if let player = viewModel.vm.player {
                AVPlayerViewControllerRepresentable(player: player)
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
        }
        .onAppear { load() }
        .onDisappear { saveWatchProgress(); viewModel.vm.cleanup() }
        .onMoveCommand { direction in
            switch direction {
            case .up:    viewModel.vm.previousChannel()
            case .down:  viewModel.vm.nextChannel()
            default:     break
            }
        }
    }
#endif

    // MARK: - iOS / macOS: Custom overlay

#if !os(tvOS)
    private var nonTVPlayerBody: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let player = viewModel.vm.player {
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
        .statusBarHidden(true)
        .onAppear { load() }
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
        guard let url = URL(string: streamURL) else { return }
        if let profile = activeProfile {
            viewModel.vm.configureSource(profile: profile)
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
}

// MARK: - tvOS AVPlayerViewController wrapper

#if os(tvOS)
struct AVPlayerViewControllerRepresentable: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.player = player
        vc.showsPlaybackControls = true
        vc.allowsPictureInPicturePlayback = false
        return vc
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        if uiViewController.player !== player {
            uiViewController.player = player
        }
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
            .navigationBarTitleDisplayMode(.inline)
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
