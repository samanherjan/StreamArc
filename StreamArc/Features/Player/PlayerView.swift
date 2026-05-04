import StreamArcCore
import SwiftUI
import SwiftData
import KSPlayer

struct PlayerView: View {

    let streamURL: String
    var title: String = ""
    var posterURL: String? = nil
    var contentType: String = "vod"
    var isLiveTV: Bool = false
    var channel: Channel? = nil
    var allChannels: [Channel] = []
    /// Resume position in seconds; 0 = start from beginning.
    var startPosition: Double = 0
    /// Pass the active profile directly to eliminate the @Query race condition.
    var profile: Profile? = nil
    /// Stable content identifier (use episode.id for episodes, item.id for VOD).
    var contentId: String? = nil
    /// Series ID — set when playing an episode so history is linked to the series.
    var seriesId: String? = nil
    var seasonNumber: Int = 0
    var episodeNumber: Int = 0
    /// All seasons of the series — used to auto-queue the next episode when this one finishes.
    var allSeasons: [Season] = []

    @StateObject private var viewModel = PlayerViewModelBridge()

    @Environment(\.dismiss) private var dismiss
    @Environment(EntitlementManager.self) private var entitlements
    @Environment(\.modelContext) private var modelContext

    @Query(filter: #Predicate<Profile> { $0.isActive == true })
    private var activeProfiles: [Profile]
    private var activeProfile: Profile? { activeProfiles.first }

    var body: some View {
        Group {
            if let ksURL = viewModel.vm.ksPlayerURL,
               let ksOptions = viewModel.vm.ksPlayerOptions,
               let ksCoordinator = viewModel.vm.ksPlayerCoordinator {
                // KSPlayer is ready — show its native view with full built-in controls UI.
                // No custom overlays are added here so KSPlayer's own toolbar, seek bar,
                // loading indicator and error handling are fully visible and functional.
                KSVideoPlayerView(
                    coordinator: ksCoordinator,
                    url: ksURL,
                    options: ksOptions,
                    title: title.isEmpty ? nil : title
                )
                .ignoresSafeArea()
            } else if let error = viewModel.vm.error {
                // Pre-playback error (URL resolution failed before KSPlayer could start).
                ZStack {
                    Color.black.ignoresSafeArea()
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
                    .padding()
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            } else {
                // URL is still resolving — minimal placeholder before KSPlayer launches.
                Color.black
                    .ignoresSafeArea()
                    .overlay {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                            .scaleEffect(1.5)
                    }
            }
        }
#if os(iOS)
        .statusBarHidden(true)
        .ignoresSafeArea()
#endif
        .task { load() }
        .onDisappear { saveWatchProgress(); viewModel.vm.cleanup() }
    }

    // MARK: - Helpers

    private func load() {
        guard !streamURL.isEmpty else {
            viewModel.vm.setError("No stream URL provided.")
            return
        }

        let sanitized = streamURL.trimmingCharacters(in: .whitespacesAndNewlines)

        let encodedSanitized = sanitized.addingPercentEncoding(
            withAllowedCharacters: .urlQueryAllowed
                .union(.urlHostAllowed)
                .union(.urlPathAllowed)) ?? sanitized
        guard let url = URL(string: sanitized) ??
              URL(string: encodedSanitized)
        else {
            viewModel.vm.setError("Invalid stream URL.")
            return
        }

        if let resolvedProfile = profile ?? activeProfile {
            viewModel.vm.configureSource(profile: resolvedProfile)
        }
        let idx = allChannels.firstIndex(where: { $0.streamURL == streamURL }) ?? 0
        viewModel.vm.pendingSeekPosition = startPosition
        viewModel.vm.setup(url: url, channels: allChannels, currentIndex: idx)
    }

    private func saveWatchProgress() {
        guard !isLiveTV else { return }
        let resolvedId = contentId ?? channel?.id ?? streamURL
        let mgr = WatchHistoryManager(modelContext: modelContext)
        let currentTime = viewModel.vm.currentTime
        let duration = viewModel.vm.duration
        try? mgr.record(
            contentId: resolvedId,
            contentType: contentType,
            title: title,
            imageURL: isLiveTV ? channel?.logoURL : posterURL,
            position: currentTime,
            duration: duration
        )
    }
}

// Bridge to use @StateObject with @Observable PlayerViewModel
@MainActor
final class PlayerViewModelBridge: ObservableObject {
    let vm = PlayerViewModel()
}
