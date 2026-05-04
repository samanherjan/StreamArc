import StreamArcCore
import SwiftUI
import Kingfisher
import SwiftData

struct SeriesDetailView: View {
    let series: Series
    @Environment(\.dismiss) private var dismiss
    @Environment(AppEnvironment.self) private var appEnv
    @State private var selectedSeason: Season?
    @State private var selectedEpisode: Episode?
    @State private var showPlayer = false
    @State private var tmdbDetail: TMDBDetail?
    @State private var isLoadingDetail = false
    @State private var seasons: [Season] = []
    @State private var isLoadingSeasons = false
    @State private var seasonsError: String?
    @State private var isFavorite = false

    @Environment(\.modelContext) private var modelContext

    @Query(filter: #Predicate<Profile> { $0.isActive == true })
    private var activeProfiles: [Profile]
    private var activeProfile: Profile? { activeProfiles.first }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Hero header
                    ZStack(alignment: .bottomLeading) {
                        if let posterURL = series.posterURL, let url = URL(string: posterURL) {
                            KFImage(url)
                                .resizable()
                                .scaledToFill()
                                .frame(height: 280)
                                .clipped()
                        } else {
                            Rectangle()
                                .fill(Color.saSurface)
                                .frame(height: 280)
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

                        VStack(alignment: .leading, spacing: 6) {
                            Text(series.title)
                                .font(.title.bold())
                                .foregroundStyle(.white)
                        }
                        .padding(20)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        // Metadata pills
                        HStack(spacing: 10) {
                            if let year = tmdbDetail?.yearString ?? series.year.map({ String($0) }) {
                                metadataPill(text: year)
                            }
                            if let numberOfSeasons = tmdbDetail?.numberOfSeasons, numberOfSeasons > 0 {
                                metadataPill(text: "\(numberOfSeasons) Season\(numberOfSeasons == 1 ? "" : "s")")
                            } else if !seasons.isEmpty {
                                metadataPill(text: "\(seasons.count) Season\(seasons.count == 1 ? "" : "s")")
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

                        // Trailer + Favorite buttons
                        HStack(spacing: 12) {
                            if let vodItem = series.asVODItem {
                                TrailerButton(item: vodItem)
                            }

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
                        } else if let desc = series.description, !desc.isEmpty {
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

                        if isLoadingDetail {
                            HStack {
                                Spacer()
                                ProgressView().tint(Color.saAccent)
                                Spacer()
                            }
                        }
                    }
                    .padding(.horizontal)

                    // Seasons & Episodes section
                    seasonsSection
                }
                .padding(.vertical)
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
            .task { await loadSeasons() }
            .onAppear { checkFavorite() }
        }
#if os(macOS)
        .sheet(isPresented: $showPlayer) {
            if let ep = selectedEpisode {
                PlayerView(streamURL: ep.streamURL, title: ep.title, posterURL: ep.posterURL ?? series.posterURL, contentType: "episode", profile: activeProfile, contentId: ep.id)
            }
        }
#else
        .fullScreenCover(isPresented: $showPlayer) {
            if let ep = selectedEpisode {
                PlayerView(streamURL: ep.streamURL, title: ep.title, posterURL: ep.posterURL ?? series.posterURL, contentType: "episode", profile: activeProfile, contentId: ep.id)
            }
        }
#endif
    }

    // MARK: - Seasons & Episodes

    @ViewBuilder
    private var seasonsSection: some View {
        if isLoadingSeasons {
            VStack(spacing: 12) {
                ProgressView()
                    .tint(Color.saAccent)
                Text("Loading seasons…")
                    .font(.subheadline)
                    .foregroundStyle(Color.saTextSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 30)
        } else if let error = seasonsError {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title2)
                    .foregroundStyle(Color.saTextSecondary.opacity(0.5))
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Color.saTextSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
        } else if !displaySeasons.isEmpty {
            // Season picker
            VStack(alignment: .leading, spacing: 16) {
                Text("Seasons & Episodes")
                    .font(.headline)
                    .foregroundStyle(Color.saTextPrimary)
                    .padding(.horizontal)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(displaySeasons) { season in
                            let isSelected = selectedSeason?.id == season.id
                            Button("Season \(season.seasonNumber)") {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedSeason = season
                                }
                            }
                            .font(.subheadline.bold())
                            .foregroundStyle(isSelected ? .white : Color.saTextSecondary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(isSelected ? Color.saAccent : Color.saSurface)
                            .clipShape(Capsule())
                        }
                    }
                    .padding(.horizontal)
                }

                // Episode list
                if let season = selectedSeason ?? displaySeasons.first {
                    LazyVStack(spacing: 8) {
                        ForEach(season.episodes) { episode in
                            Button {
                                selectedEpisode = episode
                                showPlayer = true
                            } label: {
                                HStack(spacing: 12) {
                                    Text("\(episode.episodeNumber)")
                                        .font(.headline.monospacedDigit())
                                        .frame(width: 36)
                                        .foregroundStyle(Color.saAccent)

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(episode.title)
                                            .font(.body)
                                            .foregroundStyle(Color.saTextPrimary)
                                            .lineLimit(1)
                                        if let desc = episode.description {
                                            Text(desc)
                                                .font(.caption)
                                                .foregroundStyle(Color.saTextSecondary)
                                                .lineLimit(2)
                                        }
                                    }

                                    Spacer()

                                    Image(systemName: "play.circle.fill")
                                        .font(.title3)
                                        .foregroundStyle(Color.saAccent)
                                }
                                .padding(14)
                                .background(Color.saSurface)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .cardFocusable()
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }

    /// Use fetched seasons if available, otherwise fall back to series.seasons
    private var displaySeasons: [Season] {
        seasons.isEmpty ? series.seasons : seasons
    }

    // MARK: - Loading

    private func loadDetail() async {
        let key = appEnv.settingsStore.tmdbAPIKey
        guard !key.isEmpty else { return }
        isLoadingDetail = true
        defer { isLoadingDetail = false }
        tmdbDetail = await TMDBClient.shared.fetchDetail(forSeries: series, apiKey: key)
    }

    private func loadSeasons() async {
        guard let profile = activeProfile else { return }
        // Only fetch if series doesn't already have seasons
        guard series.seasons.isEmpty else {
            seasons = series.seasons
            selectedSeason = seasons.first
            return
        }

        isLoadingSeasons = true
        defer { isLoadingSeasons = false }

        do {
            switch profile.sourceType {
            case .xtream:
                guard let base = profile.xtreamURL,
                      let user = profile.xtreamUsername,
                      let pass = profile.xtreamPassword else { return }
                let client = XtreamClient(config: .init(baseURL: base, username: user, password: pass))
                seasons = try await client.asSeriesSeasons(seriesId: series.id)

            case .stalker:
                guard let portal = profile.portalURL,
                      let mac    = profile.macAddress else { return }
                let client = StalkerClient(config: .init(portalURL: portal, macAddress: mac))
                try await client.authenticate()
                seasons = try await client.seriesSeasons(seriesId: series.id)

            default:
                seasonsError = "Series detail is not supported for this source type."
                return
            }

            if seasons.isEmpty {
                seasonsError = "No seasons found for this series."
            } else {
                selectedSeason = seasons.first
            }
        } catch {
            seasonsError = "Failed to load seasons: \(error.localizedDescription)"
        }
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

    private func checkFavorite() {
        let mgr = FavoritesManager(modelContext: modelContext)
        isFavorite = mgr.isFavorite(contentId: series.id)
    }

    private func toggleFavorite() {
        let mgr = FavoritesManager(modelContext: modelContext)
        try? mgr.toggleFavorite(contentId: series.id, contentType: "series", title: series.title, imageURL: series.posterURL)
        isFavorite = mgr.isFavorite(contentId: series.id)
    }
}

// Helper to create a VODItem stub from a Series for the TrailerButton
extension Series {
    var asVODItem: VODItem? {
        VODItem(id: id, title: title, posterURL: posterURL, streamURL: "", tmdbId: tmdbId, type: .series)
    }
}
