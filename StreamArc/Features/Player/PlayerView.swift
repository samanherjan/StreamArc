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

    @StateObject private var viewModel = PlayerViewModelBridge()
    @Environment(\.dismiss) private var dismiss
    @Environment(EntitlementManager.self) private var entitlements
    @Environment(\.modelContext) private var modelContext

    @Query(filter: #Predicate<Profile> { $0.isActive == true })
    private var activeProfiles: [Profile]
    private var activeProfile: Profile? { activeProfiles.first }

    @State private var showControls = true
    @State private var controlsTimer: Task<Void, Never>?

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

            if viewModel.vm.isLoading {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(2)
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

            if viewModel.vm.isLoading {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(2)
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

            // Bottom controls
            VStack(spacing: 12) {
                if !isLiveTV && viewModel.vm.duration > 0 {
                    Slider(
                        value: Binding(get: { viewModel.vm.currentTime }, set: { viewModel.vm.seek(to: $0) }),
                        in: 0...max(1, viewModel.vm.duration)
                    )
                    .tint(Color.saAccent)
                    .padding(.horizontal)
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
    }
#endif

    // MARK: - Helpers

    private func load() {
        guard let url = URL(string: streamURL) else { return }
        if let profile = activeProfile {
            viewModel.vm.configureSource(profile: profile)
        }
        let idx = allChannels.firstIndex(where: { $0.streamURL == streamURL }) ?? 0
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
