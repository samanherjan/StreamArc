import StreamArcCore
import SwiftUI

struct TrailerButton: View {
    let item: VODItem
    @Environment(EntitlementManager.self) private var entitlements
    @Environment(AppEnvironment.self) private var appEnv
    @State private var showPaywall = false
    @State private var showTrailer = false
    @State private var isLoading = false
    @State private var videoId: String?
    @State private var directURL: URL?
    @State private var showNotFound = false

    var body: some View {
        Button {
            guard entitlements.isPremium else {
                showPaywall = true
                return
            }
            Task { await findAndPlay() }
        } label: {
            HStack(spacing: 6) {
                if isLoading {
                    ProgressView().tint(.white).scaleEffect(0.8)
                } else {
                    Image(systemName: entitlements.isPremium ? "play.fill" : "lock.fill")
                }
                Text("Trailer")
            }
            .font(.subheadline.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Color.saAccent.opacity(entitlements.isPremium ? 1.0 : 0.5))
            .clipShape(Capsule())
        }
        .disabled(isLoading)
        .paywallSheet(isPresented: $showPaywall)
        #if os(tvOS)
        .fullScreenCover(isPresented: $showTrailer) {
            if let videoId {
                TrailerPlayerView(videoId: videoId, directURL: directURL)
            }
        }
        #else
        .sheet(isPresented: $showTrailer) {
            if let videoId {
                TrailerPlayerView(videoId: videoId)
            }
        }
        #endif
        .alert("Trailer Not Found", isPresented: $showNotFound) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Could not find a trailer for \"\(item.title)\".")
        }
    }

    private func findAndPlay() async {
        isLoading = true
        defer { isLoading = false }

        let apiKey = appEnv.settingsStore.tmdbAPIKey.isEmpty
            ? APIKeys.tmdb
            : appEnv.settingsStore.tmdbAPIKey

        // Step 1: Get YouTube video key from TMDB
        videoId = await TrailerService.shared.fetchYouTubeKey(for: item, apiKey: apiKey)

        guard videoId != nil else {
            showNotFound = true
            return
        }

        #if os(tvOS)
        // Step 2 (tvOS only): Try to get a direct .mp4 URL from KinoCheck
        directURL = await TrailerService.shared.fetchDirectTrailerURL(for: item, apiKey: apiKey)
        #endif

        showTrailer = true
    }
}

struct PremiumBadgeView: View {
    var label: String = "PRO"

    var body: some View {
        Text(label)
            .font(.system(size: 9, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Color.saAccent)
            .clipShape(Capsule())
    }
}
