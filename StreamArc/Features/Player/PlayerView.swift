import SwiftUI
import AVKit

struct PlayerView: View {

    let streamURL: String
    var title: String = ""
    var isLiveTV: Bool = false
    var channel: Channel? = nil
    var allChannels: [Channel] = []

    @StateObject private var viewModel = PlayerViewModelBridge()
    @Environment(\.dismiss) private var dismiss
    @Environment(EntitlementManager.self) private var entitlements
    @State private var showControls = true
    @State private var controlsTimer: Task<Void, Never>?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // AVKit player
            if let player = viewModel.vm.player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
                    .onTapGesture { toggleControls() }
            }

            // Loading indicator
            if viewModel.vm.isLoading {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(2)
            }

            // Error
            if let error = viewModel.vm.error {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.largeTitle).foregroundStyle(.red)
                    Text(error).foregroundStyle(.white).multilineTextAlignment(.center)
                }
            }

            // Controls overlay
            if showControls {
                playerControls
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showControls)
        .statusBarHidden(true)
        .onAppear { load() }
        .onDisappear { viewModel.vm.cleanup() }
#if os(tvOS)
        .onMoveCommand { direction in
            switch direction {
            case .up:    viewModel.vm.previousChannel()
            case .down:  viewModel.vm.nextChannel()
            default:     toggleControls()
            }
        }
#endif
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
#if !os(tvOS)
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
#endif
            }
            .padding()
            .background(.ultraThinMaterial.opacity(0.7))

            Spacer()

            // Bottom controls (VOD seek + channel up/down)
            VStack(spacing: 12) {
                if !isLiveTV && viewModel.vm.duration > 0 {
                    // Seek slider
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

    // MARK: - Helpers

    private func load() {
        guard let url = URL(string: streamURL) else { return }
        let idx = allChannels.firstIndex(where: { $0.streamURL == streamURL }) ?? 0
        viewModel.vm.setup(url: url, channels: allChannels, currentIndex: idx)
        scheduleHideControls()
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
final class PlayerViewModelBridge: ObservableObject {
    let vm = PlayerViewModel()
}

// MARK: - AirPlay button

#if !os(tvOS)
import AVKit

struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let v = AVRoutePickerView()
        v.tintColor = .white
        v.activeTintColor = UIColor(Color.saAccent)
        return v
    }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
#endif
