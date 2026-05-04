import StreamArcCore
import SwiftUI
import SwiftData
import Kingfisher

struct MovieDetailView: View {
    let item: VODItem
    @Environment(\.dismiss) private var dismiss
    @Environment(AppEnvironment.self) private var appEnv
    @Environment(EntitlementManager.self) private var entitlements
    @Environment(\.modelContext) private var modelContext
    @State private var showPlayer = false
    @State private var showPaywall = false
    @State private var tmdbDetail: TMDBDetail?
    @State private var isLoadingDetail = false
    @State private var isFavorite = false

    @Query(filter: #Predicate<Profile> { $0.isActive == true })
    private var activeProfiles: [Profile]
    private var activeProfile: Profile? { activeProfiles.first }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Hero poster with gradient overlay
                    ZStack(alignment: .bottomLeading) {
                        if let posterURL = item.posterURL, let url = URL(string: posterURL) {
                            KFImage(url)
                                .resizable()
                                .scaledToFill()
                                .frame(height: 400)
                                .clipped()
                        } else {
                            Rectangle()
                                .fill(Color.saSurface)
                                .frame(height: 400)
                        }

                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0.3),
                                .init(color: Color.saBackground.opacity(0.7), location: 0.6),
                                .init(color: Color.saBackground, location: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        // Title
                        Text(item.title)
                            .font(.title.bold())
                            .foregroundStyle(Color.saTextPrimary)

                        // Metadata pills
                        HStack(spacing: 10) {
                            if let year = tmdbDetail?.yearString ?? item.year.map({ String($0) }) {
                                metadataPill(text: year)
                            }
                            if let runtime = tmdbDetail?.runtime, runtime > 0 {
                                metadataPill(text: "\(runtime) min")
                            }
                            if let rating = tmdbDetail?.voteAverage, rating > 0 {
                                HStack(spacing: 3) {
                                    Image(systemName: "star.fill")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.yellow)
                                    Text(String(format: "%.1f", rating))
                                        .font(.caption.bold())
                                        .foregroundStyle(Color.saTextPrimary)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(.ultraThinMaterial)
                                .clipShape(Capsule())
                            }
                            if let status = tmdbDetail?.status {
                                metadataPill(text: status)
                            }
                        }

                        // Genres
                        if let genres = tmdbDetail?.genres, !genres.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(genres, id: \.id) { genre in
                                        Text(genre.name)
                                            .font(.caption)
                                            .foregroundStyle(Color.saAccent)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 5)
                                            .background(Color.saAccent.opacity(0.12))
                                            .clipShape(Capsule())
                                    }
                                }
                            }
                        }

                        // Tagline
                        if let tagline = tmdbDetail?.tagline, !tagline.isEmpty {
                            Text("\u{201C}\(tagline)\u{201D}")
                                .font(.subheadline.italic())
                                .foregroundStyle(Color.saTextSecondary)
                        }

                        // Action buttons
                        HStack(spacing: 12) {
                            Button {
                                showPlayer = true
                            } label: {
                                Label("Play", systemImage: "play.fill")
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 24)
                                    .padding(.vertical, 12)
                                    .background(Color.saAccent)
                                    .clipShape(Capsule())
                            }
                            .cardFocusable()

                            TrailerButton(item: item)

                            Button { toggleFavorite() } label: {
                                Image(systemName: isFavorite ? "heart.fill" : "heart")
                                    .font(.title3)
                                    .foregroundStyle(isFavorite ? .red : .white)
                                    .padding(12)
                                    .background(Color.saSurface)
                                    .clipShape(Circle())
                            }
                            .cardFocusable()
                        }

                        // Overview
                        if let overview = tmdbDetail?.overview, !overview.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Overview")
                                    .font(.headline)
                                    .foregroundStyle(Color.saTextPrimary)
                                Text(overview)
                                    .font(.body)
                                    .foregroundStyle(Color.saTextSecondary)
                                    .lineSpacing(4)
                            }
                        } else if let desc = item.description, !desc.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Overview")
                                    .font(.headline)
                                    .foregroundStyle(Color.saTextPrimary)
                                Text(desc)
                                    .font(.body)
                                    .foregroundStyle(Color.saTextSecondary)
                                    .lineSpacing(4)
                            }
                        }

                        // Category
                        if !item.groupTitle.isEmpty {
                            Label(item.groupTitle, systemImage: "folder")
                                .font(.caption)
                                .foregroundStyle(Color.saTextSecondary)
                        }

                        if isLoadingDetail {
                            HStack {
                                Spacer()
                                ProgressView()
                                    .tint(Color.saAccent)
                                Spacer()
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 32)
                }
            }
            .background(Color.saBackground)
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await loadDetail() }
            .onAppear { checkFavorite() }
        }
#if os(macOS)
        .sheet(isPresented: $showPlayer) {
            PlayerView(streamURL: item.streamURL, title: item.title, posterURL: item.posterURL, contentType: "vod", profile: activeProfile, contentId: item.id)
        }
#else
        .fullScreenCover(isPresented: $showPlayer) {
            PlayerView(streamURL: item.streamURL, title: item.title, posterURL: item.posterURL, contentType: "vod", profile: activeProfile, contentId: item.id)
        }
#endif
    }

    private func checkFavorite() {
        let mgr = FavoritesManager(modelContext: modelContext)
        isFavorite = mgr.isFavorite(contentId: item.id)
    }

    private func toggleFavorite() {
        let mgr = FavoritesManager(modelContext: modelContext)
        try? mgr.toggleFavorite(contentId: item.id, contentType: "vod", title: item.title, imageURL: item.posterURL)
        isFavorite = mgr.isFavorite(contentId: item.id)
    }

    private func metadataPill(text: String) -> some View {
        Text(text)
            .font(.caption.bold())
            .foregroundStyle(Color.saTextSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
    }

    private func loadDetail() async {
        let key = appEnv.settingsStore.tmdbAPIKey
        guard !key.isEmpty else { return }
        isLoadingDetail = true
        defer { isLoadingDetail = false }
        tmdbDetail = await TMDBClient.shared.fetchDetail(for: item, apiKey: key)
    }
}
