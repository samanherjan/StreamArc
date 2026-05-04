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

    private var displaySeasons: [Season] { seasons.isEmpty ? series.seasons : seasons }

    var body: some View {
        #if os(tvOS)
        tvOSBody
        #else
        defaultBody
        #endif
    }

    // MARK: - tvOS: Full-screen cinematic layout

    #if os(tvOS)
    private var tvOSBody: some View {
        ZStack {
            backdropLayer

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    // Top section: poster + metadata side by side
                    HStack(alignment: .top, spacing: 56) {
                        posterColumn.frame(width: 280)

                        metadataColumn
                            .padding(.top, 72)
                            .padding(.trailing, 80)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.leading, 80)
                    .frame(minHeight: 580)

                    // Episodes section below
                    if !displaySeasons.isEmpty {
                        tvEpisodesSection
                            .padding(.top, 16)
                            .padding(.bottom, 60)
                    }
                }
            }

            // Dismiss
            VStack {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(.white.opacity(0.55))
                            .padding(28)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
        }
        .ignoresSafeArea()
        .background(Color.saBackground)
        .task { await loadDetail() }
        .task { await loadSeasons() }
        .onAppear { checkFavorite() }
        .fullScreenCover(isPresented: $showPlayer) {
            if let ep = selectedEpisode {
                PlayerView(streamURL: ep.streamURL, title: ep.title,
                           posterURL: ep.posterURL ?? series.posterURL,
                           contentType: "episode", profile: activeProfile, contentId: ep.id)
            }
        }
    }

    private var backdropLayer: some View {
        ZStack {
            Color.saBackground.ignoresSafeArea()
            let imgURL = tmdbDetail?.backdropURL ?? series.posterURL.flatMap(URL.init)
            if let url = imgURL {
                KFImage(url).resizable().scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped().opacity(0.28).blur(radius: 8)
            }
            LinearGradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: Color.saBackground.opacity(0.5), location: 0.38),
                .init(color: Color.saBackground.opacity(0.88), location: 0.70),
                .init(color: Color.saBackground, location: 1),
            ], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            LinearGradient(colors: [Color.saBackground.opacity(0.72), .clear],
                           startPoint: .leading, endPoint: .trailing).ignoresSafeArea()
        }
    }

    private var posterColumn: some View {
        VStack {
            Spacer().frame(height: 72)
            if let url = series.posterURL.flatMap(URL.init) {
                KFImage(url).resizable().scaledToFill()
                    .frame(width: 280, height: 420)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: Color.saAccent.opacity(0.38), radius: 48, y: 24)
                    .overlay(RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color.white.opacity(0.09), lineWidth: 1.5))
            } else {
                RoundedRectangle(cornerRadius: 16).fill(Color.saCard)
                    .frame(width: 280, height: 420)
                    .overlay { Image(systemName: "tv").font(.system(size: 56))
                        .foregroundStyle(Color.saAccent.opacity(0.35)) }
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var metadataColumn: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(series.title)
                .font(.system(size: 50, weight: .heavy))
                .foregroundStyle(.white).lineLimit(3)
                .shadow(color: .black.opacity(0.55), radius: 8)

            HStack(spacing: 10) {
                if let year = tmdbDetail?.yearString ?? series.year.map({ String($0) }) {
                    tvPill(year, icon: "calendar")
                }
                if let ns = tmdbDetail?.numberOfSeasons, ns > 0 {
                    tvPill("\(ns) Season\(ns == 1 ? "" : "s")", icon: "tv")
                } else if !displaySeasons.isEmpty {
                    tvPill("\(displaySeasons.count) Season\(displaySeasons.count == 1 ? "" : "s")", icon: "tv")
                }
                if let rating = tmdbDetail?.voteAverage, rating > 0 {
                    HStack(spacing: 5) {
                        Image(systemName: "star.fill").font(.system(size: 17, weight: .bold)).foregroundStyle(.yellow)
                        Text(String(format: "%.1f", rating)).font(.system(size: 20, weight: .bold)).foregroundStyle(.white)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 9).background(.ultraThinMaterial).clipShape(Capsule())
                }
                if let status = tmdbDetail?.status { tvPill(status, icon: "info.circle") }
            }

            if let genres = tmdbDetail?.genres, !genres.isEmpty {
                HStack(spacing: 8) {
                    ForEach(genres.prefix(4), id: \.id) { g in
                        Text(g.name).font(.system(size: 18, weight: .medium)).foregroundStyle(Color.saAccent)
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .background(Color.saAccent.opacity(0.14)).clipShape(Capsule())
                    }
                }
            }

            if let tagline = tmdbDetail?.tagline, !tagline.isEmpty {
                Text("\u{201C}\(tagline)\u{201D}")
                    .font(.system(size: 22, weight: .light, design: .serif)).italic()
                    .foregroundStyle(Color.saTextSecondary).lineLimit(2)
            }

            // Buttons
            HStack(spacing: 20) {
                // Play first episode
                if let firstEp = (selectedSeason ?? displaySeasons.first)?.episodes.first {
                    Button {
                        selectedEpisode = firstEp
                        showPlayer = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "play.fill").font(.system(size: 22, weight: .bold))
                            Text("Play").font(.system(size: 26, weight: .bold))
                        }
                        .foregroundStyle(Color.saBackground)
                        .padding(.horizontal, 44).padding(.vertical, 18)
                        .background(Color.white).clipShape(Capsule())
                    }
                    .cardFocusable()
                }

                if let vodItem = series.asVODItem { TrailerButton(item: vodItem) }

                Button { toggleFavorite() } label: {
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                        .font(.system(size: 26)).foregroundStyle(isFavorite ? .red : .white)
                        .frame(width: 64, height: 64).background(Color.saCard).clipShape(Circle())
                }
                .cardFocusable()
            }
            .focusSection()
            .padding(.top, 4)

            let overview = tmdbDetail?.overview ?? series.description ?? ""
            if !overview.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Overview").font(.system(size: 24, weight: .semibold)).foregroundStyle(Color.saTextPrimary)
                    Text(overview).font(.system(size: 21)).foregroundStyle(Color.saTextSecondary)
                        .lineSpacing(5).lineLimit(5)
                }
                .padding(.top, 4)
            }

            if isLoadingDetail || isLoadingSeasons {
                ProgressView().tint(Color.saAccent).scaleEffect(1.3).padding(.top, 8)
            }
        }
    }

    private func tvPill(_ text: String, icon: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 14)).foregroundStyle(Color.saTextSecondary)
            Text(text).font(.system(size: 18, weight: .semibold)).foregroundStyle(Color.saTextSecondary)
        }
        .padding(.horizontal, 16).padding(.vertical, 9).background(.ultraThinMaterial).clipShape(Capsule())
    }

    // Season picker + horizontal episode shelf
    @ViewBuilder
    private var tvEpisodesSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            Divider().overlay(Color.white.opacity(0.08))

            // Season selector
            HStack(spacing: 0) {
                Text("Episodes")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(Color.saTextPrimary)
                    .padding(.leading, 80)

                Spacer()

                // Season picker as segmented-style buttons
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(displaySeasons) { season in
                            let isSel = (selectedSeason?.id ?? displaySeasons.first?.id) == season.id
                            Button("S\(season.seasonNumber)") {
                                withAnimation(.easeInOut(duration: 0.18)) { selectedSeason = season }
                            }
                            .font(.system(size: 22, weight: isSel ? .bold : .medium))
                            .foregroundStyle(isSel ? .white : Color.saTextSecondary)
                            .padding(.horizontal, 20).padding(.vertical, 10)
                            .background(isSel ? Color.saAccent : Color.saCard)
                            .clipShape(Capsule())
                            .cardFocusable()
                        }
                    }
                    .padding(.horizontal, 32)
                }
                .frame(maxWidth: 600)
                .padding(.trailing, 80)
            }
            .focusSection()

            // Episode horizontal shelf
            let currentSeason = selectedSeason ?? displaySeasons.first
            if let season = currentSeason, !season.episodes.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 20) {
                        ForEach(season.episodes) { episode in
                            Button {
                                selectedEpisode = episode
                                showPlayer = true
                            } label: {
                                tvEpisodeCard(episode)
                            }
                            .cardFocusable()
                        }
                    }
                    .padding(.horizontal, 80)
                    .padding(.vertical, 8)
                }
                .focusSection()
            } else if let error = seasonsError {
                Text(error).font(.system(size: 20)).foregroundStyle(Color.saTextSecondary).padding(.horizontal, 80)
            }
        }
    }

    private func tvEpisodeCard(_ episode: Episode) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .bottomLeading) {
                // Thumbnail / poster fallback
                if let url = (episode.posterURL ?? series.posterURL).flatMap(URL.init) {
                    KFImage(url).resizable().scaledToFill()
                        .frame(width: 320, height: 180).clipped()
                } else {
                    RoundedRectangle(cornerRadius: 0).fill(Color.saCard)
                        .frame(width: 320, height: 180)
                        .overlay { Image(systemName: "play.rectangle").font(.system(size: 40))
                            .foregroundStyle(Color.saAccent.opacity(0.4)) }
                }
                // Episode number badge
                Text("E\(episode.episodeNumber)")
                    .font(.system(size: 16, weight: .black))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Color.saAccent)
                    .clipShape(Capsule())
                    .padding(10)
            }
            .frame(width: 320, height: 180)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.07), lineWidth: 1))

            Text(episode.title)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.saTextPrimary)
                .lineLimit(1)
                .frame(width: 320, alignment: .leading)

            if let desc = episode.description {
                Text(desc)
                    .font(.system(size: 16))
                    .foregroundStyle(Color.saTextSecondary)
                    .lineLimit(2)
                    .frame(width: 320, alignment: .leading)
            }
        }
        .frame(width: 320)
    }
    #endif

    // MARK: - iOS / macOS default body

    private var defaultBody: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ZStack(alignment: .bottomLeading) {
                        if let url = series.posterURL.flatMap(URL.init) {
                            KFImage(url).resizable().scaledToFill().frame(height: 280).clipped()
                        } else {
                            Rectangle().fill(Color.saSurface).frame(height: 280)
                        }
                        LinearGradient(stops: [
                            .init(color: .clear, location: 0.3),
                            .init(color: Color.saBackground.opacity(0.7), location: 0.6),
                            .init(color: Color.saBackground, location: 1.0)
                        ], startPoint: .top, endPoint: .bottom)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(series.title).font(.title.bold()).foregroundStyle(.white)
                        }
                        .padding(20)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 10) {
                            if let year = tmdbDetail?.yearString ?? series.year.map({ String($0) }) { metadataPill(text: year) }
                            if let ns = tmdbDetail?.numberOfSeasons, ns > 0 { metadataPill(text: "\(ns) Season\(ns == 1 ? "" : "s")") }
                            else if !displaySeasons.isEmpty { metadataPill(text: "\(displaySeasons.count) Season\(displaySeasons.count == 1 ? "" : "s")") }
                            if let r = tmdbDetail?.voteAverage, r > 0 {
                                HStack(spacing: 3) {
                                    Image(systemName: "star.fill").font(.system(size: 10)).foregroundStyle(.yellow)
                                    Text(String(format: "%.1f", r)).font(.caption.bold()).foregroundStyle(Color.saTextPrimary)
                                }
                                .padding(.horizontal, 10).padding(.vertical, 5).background(.ultraThinMaterial).clipShape(Capsule())
                            }
                            if let s = tmdbDetail?.status { metadataPill(text: s) }
                        }

                        if let genres = tmdbDetail?.genres, !genres.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(genres, id: \.id) { g in
                                        Text(g.name).font(.caption).foregroundStyle(Color.saAccent)
                                            .padding(.horizontal, 10).padding(.vertical, 5)
                                            .background(Color.saAccent.opacity(0.12)).clipShape(Capsule())
                                    }
                                }
                            }
                        }

                        if let tagline = tmdbDetail?.tagline, !tagline.isEmpty {
                            Text("\u{201C}\(tagline)\u{201D}").font(.subheadline.italic()).foregroundStyle(Color.saTextSecondary)
                        }

                        HStack(spacing: 12) {
                            if let vodItem = series.asVODItem { TrailerButton(item: vodItem) }
                            Button { toggleFavorite() } label: {
                                Image(systemName: isFavorite ? "heart.fill" : "heart").font(.title3)
                                    .foregroundStyle(isFavorite ? .red : .white)
                                    .padding(12).background(Color.saSurface).clipShape(Circle())
                            }
                            .cardFocusable()
                        }

                        let overview = tmdbDetail?.overview ?? series.description ?? ""
                        if !overview.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Overview").font(.headline).foregroundStyle(Color.saTextPrimary)
                                Text(overview).font(.body).foregroundStyle(Color.saTextSecondary).lineSpacing(4)
                            }
                        }
                        if isLoadingDetail {
                            HStack { Spacer(); ProgressView().tint(Color.saAccent); Spacer() }
                        }
                    }
                    .padding(.horizontal)

                    defaultSeasonsSection
                }
                .padding(.vertical)
            }
            .background(Color.saBackground)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
            .task { await loadDetail() }
            .task { await loadSeasons() }
            .onAppear { checkFavorite() }
        }
        #if os(macOS)
        .sheet(isPresented: $showPlayer) {
            if let ep = selectedEpisode {
                PlayerView(streamURL: ep.streamURL, title: ep.title,
                           posterURL: ep.posterURL ?? series.posterURL,
                           contentType: "episode", profile: activeProfile, contentId: ep.id)
            }
        }
        #else
        .fullScreenCover(isPresented: $showPlayer) {
            if let ep = selectedEpisode {
                PlayerView(streamURL: ep.streamURL, title: ep.title,
                           posterURL: ep.posterURL ?? series.posterURL,
                           contentType: "episode", profile: activeProfile, contentId: ep.id)
            }
        }
        #endif
    }

    @ViewBuilder
    private var defaultSeasonsSection: some View {
        if isLoadingSeasons {
            VStack(spacing: 12) { ProgressView().tint(Color.saAccent); Text("Loading seasons…").font(.subheadline).foregroundStyle(Color.saTextSecondary) }
                .frame(maxWidth: .infinity).padding(.vertical, 30)
        } else if let error = seasonsError {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle").font(.title2).foregroundStyle(Color.saTextSecondary.opacity(0.5))
                Text(error).font(.caption).foregroundStyle(Color.saTextSecondary).multilineTextAlignment(.center)
            }.frame(maxWidth: .infinity).padding(.vertical, 20)
        } else if !displaySeasons.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                Text("Seasons & Episodes").font(.headline).foregroundStyle(Color.saTextPrimary).padding(.horizontal)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(displaySeasons) { season in
                            let isSel = selectedSeason?.id == season.id
                            Button("Season \(season.seasonNumber)") {
                                withAnimation(.easeInOut(duration: 0.2)) { selectedSeason = season }
                            }
                            .font(.subheadline.bold())
                            .foregroundStyle(isSel ? .white : Color.saTextSecondary)
                            .padding(.horizontal, 16).padding(.vertical, 8)
                            .background(isSel ? Color.saAccent : Color.saSurface)
                            .clipShape(Capsule())
                        }
                    }
                    .padding(.horizontal)
                }

                if let season = selectedSeason ?? displaySeasons.first {
                    LazyVStack(spacing: 8) {
                        ForEach(season.episodes) { episode in
                            Button {
                                selectedEpisode = episode; showPlayer = true
                            } label: {
                                HStack(spacing: 12) {
                                    Text("\(episode.episodeNumber)").font(.headline.monospacedDigit())
                                        .frame(width: 36).foregroundStyle(Color.saAccent)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(episode.title).font(.body).foregroundStyle(Color.saTextPrimary).lineLimit(1)
                                        if let desc = episode.description {
                                            Text(desc).font(.caption).foregroundStyle(Color.saTextSecondary).lineLimit(2)
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: "play.circle.fill").font(.title3).foregroundStyle(Color.saAccent)
                                }
                                .padding(14).background(Color.saSurface)
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

    // MARK: - Shared helpers

    private func metadataPill(text: String) -> some View {
        Text(text).font(.caption.bold()).foregroundStyle(Color.saTextSecondary)
            .padding(.horizontal, 10).padding(.vertical, 5).background(.ultraThinMaterial).clipShape(Capsule())
    }

    private func checkFavorite() {
        isFavorite = FavoritesManager(modelContext: modelContext).isFavorite(contentId: series.id)
    }

    private func toggleFavorite() {
        let mgr = FavoritesManager(modelContext: modelContext)
        try? mgr.toggleFavorite(contentId: series.id, contentType: "series",
                                title: series.title, imageURL: series.posterURL)
        isFavorite = mgr.isFavorite(contentId: series.id)
    }

    private func loadDetail() async {
        let key = appEnv.settingsStore.tmdbAPIKey
        guard !key.isEmpty else { return }
        isLoadingDetail = true
        defer { isLoadingDetail = false }
        tmdbDetail = await TMDBClient.shared.fetchDetail(forSeries: series, apiKey: key)
    }

    private func loadSeasons() async {
        guard let profile = activeProfile else { return }
        guard series.seasons.isEmpty else { seasons = series.seasons; selectedSeason = seasons.first; return }
        isLoadingSeasons = true; defer { isLoadingSeasons = false }
        do {
            switch profile.sourceType {
            case .xtream:
                guard let base = profile.xtreamURL, let user = profile.xtreamUsername,
                      let pass = profile.xtreamPassword else { return }
                seasons = try await XtreamClient(config: .init(baseURL: base, username: user, password: pass)).asSeriesSeasons(seriesId: series.id)
            case .stalker:
                guard let portal = profile.portalURL, let mac = profile.macAddress else { return }
                let client = StalkerClient(config: .init(portalURL: portal, macAddress: mac))
                try await client.authenticate()
                seasons = try await client.seriesSeasons(seriesId: series.id)
            default:
                seasonsError = "Series detail is not supported for this source type."
                return
            }
            if seasons.isEmpty { seasonsError = "No seasons found for this series." }
            else { selectedSeason = seasons.first }
        } catch { seasonsError = "Failed to load seasons: \(error.localizedDescription)" }
    }
}

extension Series {
    var asVODItem: VODItem? {
        VODItem(id: id, title: title, posterURL: posterURL, streamURL: "", tmdbId: tmdbId, type: .series)
    }
}
