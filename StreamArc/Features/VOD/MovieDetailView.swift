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
    @State private var cast: [TMDBCastMember] = []
    @State private var similarItems: [TMDBSimilarItem] = []
    @State private var contentRating: String?
    @State private var overviewExpanded = false
    @State private var savedPosition: Double = 0
    @State private var savedDuration: Double = 0

    @Query(filter: #Predicate<Profile> { $0.isActive == true })
    private var activeProfiles: [Profile]
    private var activeProfile: Profile? { activeProfiles.first }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {

                    // ── Cinematic Hero ──────────────────────────────────
                    heroHeader

                    // ── Poster + Metadata ───────────────────────────────
                    HStack(alignment: .top, spacing: 16) {
                        // Thumbnail poster (Plex style — small inset)
                        posterThumbnail
                            .frame(width: 100)
                            .offset(y: -50)
                            .padding(.leading, 20)

                        // Title + pills
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.title)
                                .font(.title2.bold())
                                .foregroundStyle(Color.saTextPrimary)
                                .lineLimit(3)
                                .padding(.top, 12)

                            metaRow
                        }
                        .padding(.trailing, 16)
                    }
                    .padding(.bottom, 4)

                    // ── Content body ────────────────────────────────────
                    VStack(alignment: .leading, spacing: 20) {

                        // Genres
                        if let genres = tmdbDetail?.genres, !genres.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(genres, id: \.id) {
                                        GenreTag(name: $0.name)
                                    }
                                }
                            }
                        }

                        // Action buttons
                        actionButtons

                        // Tagline
                        if let tagline = tmdbDetail?.tagline, !tagline.isEmpty {
                            Text("\u{201C}\(tagline)\u{201D}")
                                .font(.subheadline.italic())
                                .foregroundStyle(Color.saTextSecondary)
                        }

                        // Overview
                        let overview = tmdbDetail?.overview ?? item.description ?? ""
                        if !overview.isEmpty {
                            overviewSection(text: overview)
                        }

                        // Cast
                        if !cast.isEmpty { castSection }

                        // More Like This
                        if !similarItems.isEmpty { similarSection }

                        if isLoadingDetail {
                            HStack { Spacer(); ProgressView().tint(Color.saAccent); Spacer() }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
            }
            .background(Color.saBackground.ignoresSafeArea())
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await loadDetail() }
            .onAppear {
                checkFavorite()
                loadSavedProgress()
            }
        }
        #if os(macOS)
        .sheet(isPresented: $showPlayer) {
            PlayerView(streamURL: item.streamURL, title: item.title, posterURL: item.posterURL,
                       contentType: "vod", startPosition: savedPosition,
                       profile: activeProfile, contentId: item.id)
        }
        #else
        .fullScreenCover(isPresented: $showPlayer) {
            PlayerView(streamURL: item.streamURL, title: item.title, posterURL: item.posterURL,
                       contentType: "vod", startPosition: savedPosition,
                       profile: activeProfile, contentId: item.id)
        }
        #endif
    }

    // MARK: - Hero Header

    private var heroHeader: some View {
        ZStack(alignment: .bottom) {
            let backdropURL = tmdbDetail?.backdropURL
            let posterURL   = item.posterURL.flatMap { URL(string: $0) }
            let isUsingPoster = backdropURL == nil

            Group {
                if let url = backdropURL ?? posterURL {
                    KFImage(url).resizable().scaledToFill()
                        .frame(maxWidth: .infinity).frame(height: 300).clipped()
                        // When we only have a portrait poster, blur + dim it so it
                        // acts as an atmospheric background rather than a cropped image.
                        .blur(radius: isUsingPoster ? 22 : 0)
                        .opacity(isUsingPoster ? 0.45 : 1)
                } else {
                    LinearGradient(
                        colors: [Color.saSurface, Color.saBackground],
                        startPoint: .top, endPoint: .bottom
                    )
                    .frame(height: 300)
                }
            }

            // Gradient fade into the page background
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.0),
                    .init(color: Color.saBackground.opacity(0.35), location: 0.5),
                    .init(color: Color.saBackground.opacity(0.90), location: 0.80),
                    .init(color: Color.saBackground, location: 1.0)
                ],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 300)
        }
    }

    // MARK: - Poster Thumbnail

    private var posterThumbnail: some View {
        Group {
            if let url = item.posterURL.flatMap(URL.init) {
                KFImage(url).resizable()
                    .placeholder { ShimmerCard() }
                    .fade(duration: 0.2)
                    .scaledToFill()
                    .aspectRatio(2/3, contentMode: .fit)
            } else {
                Rectangle().fill(Color.saSurface)
                    .aspectRatio(2/3, contentMode: .fit)
                    .overlay(Image(systemName: "film")
                        .foregroundStyle(Color.saTextSecondary.opacity(0.3)))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(Color.white.opacity(0.1), lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 12, y: 6)
    }

    // MARK: - Metadata row

    private var metaRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if let year = tmdbDetail?.yearString ?? item.year.map({ String($0) }) {
                    metaPill(year)
                }
                if let runtime = tmdbDetail?.runtime, runtime > 0 {
                    metaPill("\(runtime) min")
                }
                if let rating = tmdbDetail?.voteAverage, rating > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "star.fill").font(.system(size: 9)).foregroundStyle(.yellow)
                        Text(String(format: "%.1f", rating)).font(.caption.bold()).foregroundStyle(Color.saTextPrimary)
                    }
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(.ultraThinMaterial).clipShape(Capsule())
                }
                if let cr = contentRating {
                    Text(cr).font(.caption.bold()).foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(Color.gray.opacity(0.45))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                if let status = tmdbDetail?.status {
                    metaPill(status)
                }
            }
        }
    }

    private func metaPill(_ text: String) -> some View {
        Text(text).font(.caption.bold()).foregroundStyle(Color.saTextSecondary)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(.ultraThinMaterial).clipShape(Capsule())
    }

    // MARK: - Action Buttons (Plex-style)

    private var actionButtons: some View {
        VStack(spacing: 10) {
            // Progress bar (shown only when there is saved progress)
            let progress = savedDuration > 0 ? min(1, savedPosition / savedDuration) : 0
            if progress > 0 && progress < 0.9 {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.15)).frame(height: 4)
                        Capsule().fill(Color.saAccent)
                            .frame(width: geo.size.width * progress, height: 4)
                    }
                }
                .frame(height: 4)
            }

            // Primary: Play / Resume
            Button { showPlayer = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill").font(.headline)
                    Text(progress > 0.01 && progress < 0.9 ? "Resume" : "Play").font(.headline.bold())
                    Spacer()
                    if progress > 0.01 && progress < 0.9 {
                        Text(formatTime(savedPosition))
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 20).padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                .background(Color.saAccent)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .cardFocusable()

            // Secondary row: Trailer + Favourite
            HStack(spacing: 10) {
                TrailerButton(item: item)

                Button { toggleFavorite() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isFavorite ? "heart.fill" : "heart")
                            .foregroundStyle(isFavorite ? .red : Color.saTextPrimary)
                        Text(isFavorite ? "Saved" : "Save")
                            .font(.subheadline.bold())
                            .foregroundStyle(Color.saTextPrimary)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .background(Color.saCard)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1))
                }
                .cardFocusable()
            }
        }
    }

    // MARK: - Overview Section

    private func overviewSection(text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Overview")
                .font(.headline.bold())
                .foregroundStyle(Color.saTextPrimary)

            Text(text)
                .font(.body)
                .foregroundStyle(Color.saTextSecondary)
                .lineSpacing(4)
                .lineLimit(overviewExpanded ? nil : 4)

            if text.count > 180 {
                Button(overviewExpanded ? "Less" : "More") {
                    withAnimation(.easeInOut(duration: 0.2)) { overviewExpanded.toggle() }
                }
                .font(.caption.bold())
                .foregroundStyle(Color.saAccent)
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(Color.saSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Cast Section

    private var castSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Cast")
                .font(.headline.bold())
                .foregroundStyle(Color.saTextPrimary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(cast, id: \.id) { member in
                        CastMemberCard(member: member)
                    }
                }
            }
        }
    }

    // MARK: - Similar Section

    private var similarSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("More Like This")
                .font(.headline.bold())
                .foregroundStyle(Color.saTextPrimary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(similarItems) { sim in SimilarItemCard(item: sim) }
                }
            }
        }
    }

    // MARK: - Helpers

    private func checkFavorite() {
        let mgr = FavoritesManager(modelContext: modelContext)
        isFavorite = mgr.isFavorite(contentId: item.id)
    }

    private func toggleFavorite() {
        let mgr = FavoritesManager(modelContext: modelContext)
        try? mgr.toggleFavorite(contentId: item.id, contentType: "vod", title: item.title, imageURL: item.posterURL)
        isFavorite = mgr.isFavorite(contentId: item.id)
    }

    private func loadDetail() async {
        let key = appEnv.settingsStore.tmdbAPIKey
        guard !key.isEmpty else { return }
        isLoadingDetail = true
        defer { isLoadingDetail = false }
        tmdbDetail = await TMDBClient.shared.fetchDetail(for: item, apiKey: key)
        guard let detail = tmdbDetail else { return }
        let mediaType: TMDBMediaType = item.type == .series ? .tv : .movie
        async let c  = (try? await TMDBClient.shared.cast(tmdbId: detail.id, mediaType: mediaType, apiKey: key)) ?? []
        async let s  = (try? await TMDBClient.shared.similar(tmdbId: detail.id, mediaType: mediaType, apiKey: key)) ?? []
        async let cr = try? await TMDBClient.shared.contentRating(tmdbId: detail.id, mediaType: mediaType, apiKey: key)
        let (castResult, simResult, ratingResult) = await (c, s, cr)
        cast = castResult
        similarItems = simResult
        contentRating = ratingResult
    }

    private func loadSavedProgress() {
        let mgr = WatchHistoryManager(modelContext: modelContext)
        if let e = mgr.entry(for: item.id) {
            savedPosition = e.lastPosition
            savedDuration = e.duration
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        let s = Int(seconds)
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec)
                     : String(format: "%d:%02d", m, sec)
    }
}

// MARK: - Cast Member Card (shared with SeriesDetailView)

struct CastMemberCard: View {
    let member: TMDBCastMember

    var body: some View {
        VStack(spacing: 6) {
            if let url = member.profileURL {
                KFImage(url).resizable()
                    .placeholder {
                        Circle().fill(Color.saSurface)
                            .overlay(Image(systemName: "person.fill")
                                .foregroundStyle(Color.saTextSecondary.opacity(0.4)))
                    }
                    .fade(duration: 0.2).scaledToFill()
                    .frame(width: 64, height: 64).clipShape(Circle())
            } else {
                Circle().fill(Color.saSurface).frame(width: 64, height: 64)
                    .overlay(Image(systemName: "person.fill")
                        .foregroundStyle(Color.saTextSecondary.opacity(0.4)))
            }
            Text(member.name)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.saTextPrimary)
                .lineLimit(2).multilineTextAlignment(.center).frame(width: 70)
            if let character = member.character, !character.isEmpty {
                Text(character).font(.system(size: 10))
                    .foregroundStyle(Color.saTextSecondary).lineLimit(1).frame(width: 70)
            }
        }
    }
}

// MARK: - Similar Item Card (shared with SeriesDetailView)

struct SimilarItemCard: View {
    let item: TMDBSimilarItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let url = item.posterURL {
                KFImage(url).resizable().placeholder { ShimmerCard() }
                    .fade(duration: 0.2).scaledToFill()
                    .aspectRatio(2/3, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                Rectangle().fill(Color.saSurface)
                    .aspectRatio(2/3, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(Image(systemName: "film")
                        .foregroundStyle(Color.saTextSecondary.opacity(0.3)))
            }
            Text(item.displayTitle).font(.caption)
                .foregroundStyle(Color.saTextSecondary).lineLimit(2)
        }
        .frame(width: 100)
    }
}
