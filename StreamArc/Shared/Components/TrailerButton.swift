import SwiftUI

struct TrailerButton: View {
    let item: VODItem
    @Environment(AppEnvironment.self) private var appEnv
    @Environment(EntitlementManager.self) private var entitlements
    @State private var trailerURL: URL?
    @State private var isLoading = false
    @State private var showPaywall = false
    @State private var showTrailer = false

    var body: some View {
        Button {
            guard entitlements.isPremium else {
                showPaywall = true
                return
            }
            Task { await loadTrailer() }
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
        .sheet(isPresented: $showTrailer) {
            if let url = trailerURL {
                TrailerPlayerView(url: url)
            }
        }
    }

    private func loadTrailer() async {
        let key = appEnv.settingsStore.tmdbAPIKey
        guard !key.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        trailerURL = await TMDBClient.shared.trailerURL(for: item, apiKey: key)
        if trailerURL != nil { showTrailer = true }
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
