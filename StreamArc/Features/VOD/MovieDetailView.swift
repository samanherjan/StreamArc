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
        #if os(tvOS)
        tvOSBody
        #else
        defaultBody
        #endif
    }

    // MARK: - tvOS cinematic full-screen layout

    #if os(tvOS)
    private var tvOSBody: some View {
        ZStack {
            backdropLayer

            HStack(alignment: .top, spacing: 56) {
                posterColumn.frame(width: 280)

                ScrollView(.vertical, showsIndicators: false) {
                    metadataColumn
                        .padding(.top, 72)
                        .padding(.bottom, 60)
                        .padding(.trailing, 80)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.leading, 80)

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
        .onAppear { checkFavorite() }
        .fullScreenCover(isPresented: $showPlayer) {
            PlayerView(streamURL: item.streamURL, title: item.title,
                       posterURL: item.posterURL, contentType: "vod",
                       profile: activeProfile, contentId: item.id)
        }
        .paywallSheet(isPresented: $showPaywall)
    }

    private var backdropLayer: some View {
        ZStack {
            Color.saBackground.ignoresSafeArea()
            let imgURL = tmdbDetail?.backdropURL ?? item.posterURL.flatMap(URL.init)
            if let url = imgURL {
                KFImage(url)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .opacity(0.30)
                    .blur(radius: 8)
            }
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: Color.saBackground.opacity(0.5), location: 0.4),
                    .init(color: Color.saBackground.opacity(0.88), location: 0.72),
                    .init(color: Color.saBackground, location: 1),
                ],
                startPoint: .top, endPoint: .bottom
            ).ignoresSafeArea()
            LinearGradient(
                colors: [Color.saBackground.opacity(0.75), .clear],
                startPoint: .leading, endPoint: .trailing
            ).ignoresSafeArea()
        }
    }

    private var posterColumn: some View {
        VStack {
            Spacer().frame(height: 72)
            if let url = item.posterURL.flatMap(URL.init) {
                KFImage(url)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 280, height: 420)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: Color.saAccent.opacity(0.40), radius: 48, y: 24)
                    .overlay(RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color.white.opacity(0.09), lineWidth: 1.5))
            } else {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.saCard)
                    .frame(width: 280, height: 420)
                    .overlay {
                        Image(systemName: "film")
                            .font(.system(size: 56))
                            .foregroundStyle(Color.saAccent.opacity(0.35))
                    }
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var metadataColumn: some View {
        VStack(alignment: .leading, spacing: 20) {

            // Title
            Text(item.title)
                .font(.system(size: 50, weight: .heavy))
                .foregroundStyle(.white)
                .lineLimit(3)
                .shadow(color: .black.opacity(0.55), radius: 8)

            // Meta pills
            HStack(spacing: 10) {
                if let year = tmdbDetail?.yearString ?? item.year.map({ String($0) }) {
                    tvPill(year, icon: "calendar")
                }
                if let runtime = tmdbDetail?.runtime, runtime > 0 {
                    tvPill("\(runtime) min", icon: "clock")
                }
                if let rating = tmdbDetail?.voteAverage, rating > 0 {
                    HStack(spacing: 5) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.yellow)
                        Text(String(format: "%.1f", rating))
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                }
                if let status = tmdbDetail?.status {
                    tvPill(status, icon: "info.circle")
                }
            }

            // Genres
            if let genres = tmdbDetail?.genres, !genres.isEmpty {
                HStack(spacing: 8) {
                    ForEach(genres.prefix(4), id: \.id) { g in
                        Text(g.name)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(Color.saAccent)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(Color.saAccent.opacity(0.14))
                            .clipShape(Capsule())
                    }
                }
            }

            // Tagline
            if let tagline = tmdbDetail?.tagline, !tagline.isEmpty {
                Text("\u{201C}\(tagline)\u{201D}")
                    .font(.system(size: 22, weight: .light, design: .serif))
                    .italic()
                    .foregroundStyle(Color.saTextSecondary)
                    .lineLimit(2)
            }

            // Action buttons
            HStack(spacing: 20) {
                Button { showPlayer = true } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "play.fill").font(.system(size: 22, weight: .bold))
                        Text("Play").font(.system(size: 26, weight: .bold))
                    }
                    .foregroundStyle(Color.saBackground)
                    .padding(.horizontal, 44)
                    .padding(.vertical, 18)
                    .background(Color.white)
                    .clipShape(Capsule())
                }
                .cardFocusable()

                TrailerButton(item: item)

                Button { toggleFavorite() } label: {
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                        .font(.system(size: 26))
                        .foregroundStyle(isFavorite ? .red : .white)
                        .frame(width: 64, height: 64)
                        .background(Color.saCard)
                        .clipShape(Circle())
                }
                .cardFocusable()
            }
            .focusSection()
            .padding(.top, 4)

            // Overview
            let overview = tmdbDetail?.overview ?? item.description ?? ""
            if !overview.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Overview")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(Color.saTextPrimary)
                    Text(overview)
                        .font(.system(size: 21))
                        .foregroundStyle(Color.saTextSecondary)
                        .lineSpacing(5)
                        .lineLimit(7)
                }
                .padding(.top, 4)
            }

            if isLoadingDetail {
                ProgressView().tint(Color.saAccent).scaleEffect(1.3).padding(.top, 8)
            }
        }
    }

    private func tvPill(_ text: String, icon: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 14)).foregroundStyle(Color.saTextSecondary)
            Text(text).font(.system(size: 18, weight: .semibold)).foregroundStyle(Color.saTextSecondary)
        }
        .padding(.horizontal, 16).padding(.vertical, 9)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
    }
    #endif

    // MARK: - iOS / macOS default body

    private var defaultBody: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ZStack(alignment: .bottomLeading) {
                        if let url = item.posterURL.flatMap(URL.init) {
                            KFImage(url).resizable().scaledToFill()
                                .frame(height: 400).clipped()
                        } else {
                            Rectangle().fill(Color.saSurface).frame(height: 400)
                        }
                        LinearGradient(stops: [
                            .init(color: .clear, location: 0.3),
                            .init(color: Color.saBackground.opacity(0.7), location: 0.6),
                            .init(color: Color.saBackground, location: 1.0)
                        ], startPoint: .top, endPoint: .bottom)
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        Text(item.title).font(.title.bold()).foregroundStyle(Color.saTextPrimary)

                        HStack(spacing: 10) {
                            if let year = tmdbDetail?.yearString ?? item.year.map({ String($0) }) { metadataPill(text: year) }
                            if let rt = tmdbDetail?.runtime, rt > 0 { metadataPill(text: "\(rt) min") }
                            if let r = tmdbDetail?.voteAverage, r > 0 {
                                HStack(spacing: 3) {
                                    Image(systemName: "star.fill").font(.system(size: 10)).foregroundStyle(.yellow)
                                    Text(String(format: "%.1f", r)).font(.caption.bold()).foregroundStyle(Color.saTextPrimary)
                                }
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(.ultraThinMaterial).clipShape(Capsule())
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
                            Button { showPlayer = true } label: {
                                Label("Play", systemImage: "play.fill").font(.headline).foregroundStyle(.white)
                                    .padding(.horizontal, 24).padding(.vertical, 12)
                                    .background(Color.saAccent).clipShape(Capsule())
                            }
                            .cardFocusable()
                            TrailerButton(item: item)
                            Button { toggleFavorite() } label: {
                                Image(systemName: isFavorite ? "heart.fill" : "heart")
                                    .font(.title3).foregroundStyle(isFavorite ? .red : .white)
                                    .padding(12).background(Color.saSurface).clipShape(Circle())
                            }
                            .cardFocusable()
                        }

                        let overview = tmdbDetail?.overview ?? item.description ?? ""
                        if !overview.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Overview").font(.headline).foregroundStyle(Color.saTextPrimary)
                                Text(overview).font(.body).foregroundStyle(Color.saTextSecondary).lineSpacing(4)
                            }
                        }

                        if !item.groupTitle.isEmpty {
                            Label(item.groupTitle, systemImage: "folder").font(.caption).foregroundStyle(Color.saTextSecondary)
                        }
                        if isLoadingDetail {
                            HStack { Spacer(); ProgressView().tint(Color.saAccent); Spacer() }
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
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
            .task { await loadDetail() }
            .onAppear { checkFavorite() }
        }
        #if os(macOS)
        .sheet(isPresented: $showPlayer) {
            PlayerView(streamURL: item.streamURL, title: item.title, posterURL: item.posterURL,
                       contentType: "vod", profile: activeProfile, contentId: item.id)
        }
        #else
        .fullScreenCover(isPresented: $showPlayer) {
            PlayerView(streamURL: item.streamURL, title: item.title, posterURL: item.posterURL,
                       contentType: "vod", profile: activeProfile, contentId: item.id)
        }
        #endif
    }

    // MARK: - Shared helpers

    private func checkFavorite() {
        isFavorite = FavoritesManager(modelContext: modelContext).isFavorite(contentId: item.id)
    }

    private func toggleFavorite() {
        let mgr = FavoritesManager(modelContext: modelContext)
        try? mgr.toggleFavorite(contentId: item.id, contentType: "vod",
                                title: item.title, imageURL: item.posterURL)
        isFavorite = mgr.isFavorite(contentId: item.id)
    }

    private func metadataPill(text: String) -> some View {
        Text(text).font(.caption.bold()).foregroundStyle(Color.saTextSecondary)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(.ultraThinMaterial).clipShape(Capsule())
    }

    private func loadDetail() async {
        let key = appEnv.settingsStore.tmdbAPIKey
        guard !key.isEmpty else { return }
        isLoadingDetail = true
        defer { isLoadingDetail = false }
        tmdbDetail = await TMDBClient.shared.fetchDetail(for: item, apiKey: key)
    }
}
