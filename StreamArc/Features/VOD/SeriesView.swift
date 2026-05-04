import StreamArcCore
import SwiftUI
import SwiftData
import Kingfisher

// MARK: - SeriesView

struct SeriesView: View {

    var viewModel: HomeViewModel

    @Environment(AppEnvironment.self)     private var appEnv
    @Environment(EntitlementManager.self) private var entitlements

    @State private var selectedSeries: Series?
    @State private var showPaywall = false
    @State private var trendingTV: [TMDBTrendingItem] = []
    @State private var selectedTMDB: TMDBTrendingItem?
    @State private var heroIndex: Int = 0
    @State private var cachedGroupedSeries: [(category: String, items: [Series])] = []
    @State private var allSeries: [Series] = []

    // Resume from Continue Watching
    @State private var resumeSeries: Series?
    @State private var resumeEpisode: (streamURL: String, title: String, posterURL: String?, position: Double)?

    @Query(sort: \FavoriteItem.addedAt, order: .reverse) private var favoriteItems: [FavoriteItem]

    private var apiKey: String {
        appEnv.settingsStore.tmdbAPIKey.isEmpty ? APIKeys.tmdb : appEnv.settingsStore.tmdbAPIKey
    }
    private var heroItems: [TMDBTrendingItem] { Array(trendingTV.prefix(6)) }
    private var recentlyAdded: [Series] { Array(viewModel.series.suffix(9).reversed()) }
    private var favoriteSeries: [Series] {
        let ids = Set(favoriteItems.filter { $0.contentType == "series" }.map(\.contentId))
        return viewModel.series.filter { ids.contains($0.id) }
    }

    private func rebuildCache() {
        let all = viewModel.series
        Task.detached(priority: .userInitiated) {
            var dict: [String: [Series]] = [:]
            for s in all {
                let key = s.groupTitle?.isEmpty == false ? s.groupTitle! : "Uncategorized"
                dict[key, default: []].append(s)
            }
            // Sort alphabetically
            let keys = dict.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            let grouped = keys.map { (category: $0, items: dict[$0]!) }
            await MainActor.run {
                self.allSeries = all
                self.cachedGroupedSeries = grouped
            }
        }
    }

    var body: some View {
        ZStack {
            Color.saBackground.ignoresSafeArea()
            if entitlements.isPremium {
                switch viewModel.loadState {
                case .idle, .loading:
                    ScrollView { ShimmerGrid(columns: 3).padding(.top, 20) }
                case .error(let msg):
                    ErrorView(message: msg)
                case .loaded:
                    mainContent
                }
            } else {
                lockedPlaceholder
            }
        }
        .task {
            if case .loaded = viewModel.loadState { rebuildCache() }
            await loadTMDB()
        }
        .onChange(of: viewModel.loadState) { _, s in if case .loaded = s { rebuildCache() } }
        #if os(tvOS)
        .fullScreenCover(item: $selectedSeries) { SeriesDetailView(series: $0) }
        #else
        .sheet(item: $selectedSeries) { SeriesDetailView(series: $0) }
        #endif
        .sheet(item: $selectedTMDB) { i in
            SeriesTMDBDiscoverySheet(item: i, seriesLibrary: viewModel.series) { selectedSeries = $0 }
        }
        #if os(tvOS)
        .fullScreenCover(item: $resumeSeries) { SeriesDetailView(series: $0) }
        #else
        .sheet(item: $resumeSeries) { SeriesDetailView(series: $0) }
        #endif
        #if os(macOS)
        .sheet(isPresented: Binding(
            get: { resumeEpisode != nil },
            set: { if !$0 { resumeEpisode = nil } }
        )) {
            if let ep = resumeEpisode {
                PlayerView(streamURL: ep.streamURL, title: ep.title,
                           posterURL: ep.posterURL, contentType: "episode",
                           startPosition: ep.position)
            }
        }
        #else
        .fullScreenCover(isPresented: Binding(
            get: { resumeEpisode != nil },
            set: { if !$0 { resumeEpisode = nil } }
        )) {
            if let ep = resumeEpisode {
                PlayerView(streamURL: ep.streamURL, title: ep.title,
                           posterURL: ep.posterURL, contentType: "episode",
                           startPosition: ep.position)
            }
        }
        #endif
        .paywallSheet(isPresented: $showPaywall)
    }

    // MARK: - Main content (ordered per spec)

    private var mainContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 0) {

                // 1. Hero Banner
                if !heroItems.isEmpty {
                    SeriesHeroCarousel(items: heroItems, heroIndex: $heroIndex) { selectedTMDB = $0 }
                        .padding(.bottom, 28)
                }

                // 2. Continue Watching
                ContinueWatchingRow(seriesLibrary: viewModel.series) { entry, nextEp in
                    if let nextEp {
                        resumeEpisode = (streamURL: nextEp.streamURL, title: nextEp.title,
                                         posterURL: nextEp.posterURL, position: 0)
                    } else if entry.contentType == "episode" {
                        if let series = viewModel.series.first(where: { s in
                            s.seasons.flatMap(\.episodes).contains(where: { $0.id == entry.contentId })
                        }), let ep = series.seasons.flatMap(\.episodes).first(where: { $0.id == entry.contentId }) {
                            resumeEpisode = (streamURL: ep.streamURL, title: entry.title,
                                             posterURL: entry.imageURL, position: entry.lastPosition)
                        }
                    } else if entry.contentType == "series" {
                        resumeSeries = viewModel.series.first { $0.id == entry.contentId }
                    }
                }
                .padding(.bottom, 4)

                // 3. Favourites
                if !favoriteSeries.isEmpty {
                    PlexShelfSection(title: "My Favourites", icon: "star.fill", iconColor: .yellow) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(alignment: .top, spacing: 10) {
                                ForEach(favoriteSeries) { s in
                                    Button { selectedSeries = s } label: { SeriesIPTVPosterCard(series: s) }
                                        .cardFocusable()
                                }
                            }
                            .padding(.horizontal).padding(.vertical, 4)
                        }
                    }
                    .padding(.bottom, 28)
                }

                // 4. Trending TV Today
                if !trendingTV.isEmpty {
                    PlexShelfSection(title: "Trending TV Today", icon: "tv.fill", iconColor: .blue) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(alignment: .top, spacing: 10) {
                                ForEach(trendingTV) { item in
                                    Button { selectedTMDB = item } label: { SeriesTMDBPosterCard(item: item) }
                                        .cardFocusable()
                                }
                            }
                            .padding(.horizontal).padding(.vertical, 4)
                        }
                    }
                    .padding(.bottom, 28)
                }

                // 5. Recently Added
                if !recentlyAdded.isEmpty {
                    PlexShelfSection(title: "Recently Added", icon: "clock.fill", iconColor: .blue) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(alignment: .top, spacing: 10) {
                                ForEach(recentlyAdded) { s in
                                    Button { selectedSeries = s } label: { SeriesIPTVPosterCard(series: s) }
                                        .cardFocusable()
                                }
                            }
                            .padding(.horizontal).padding(.vertical, 4)
                        }
                    }
                    .padding(.bottom, 28)
                }

                // 6. Your Library (All Series first, then alphabetical)
                if !cachedGroupedSeries.isEmpty || !allSeries.isEmpty {
                    PlexShelfSection(title: "Your Library", icon: "square.grid.2x2.fill", iconColor: Color.saAccent) {
                        EmptyView()
                    }
                    categoryBrowserGrid.padding(.bottom, 28)
                } else if viewModel.series.isEmpty && viewModel.loadState == .loaded {
                    EmptyContentView(title: "No Series Found",
                                     subtitle: "Your source didn't return any series. Series require Xtream or Stalker.",
                                     systemImage: "tv.and.mediabox")
                }

                Spacer(minLength: 60)
            }
        }
    }

    // MARK: - Category browser grid

    private var categoryBrowserGrid: some View {
        let cols: [GridItem] = {
            #if os(tvOS)
            return Array(repeating: GridItem(.flexible(), spacing: 20), count: 4)
            #elseif os(macOS)
            return Array(repeating: GridItem(.flexible(), spacing: 16), count: 4)
            #else
            return Array(repeating: GridItem(.flexible(), spacing: 12), count: 2)
            #endif
        }()
        return LazyVGrid(columns: cols, spacing: 16) {
            // "All Series" card — always first
            NavigationLink(destination: SeriesCategoryDetailView(category: "All Series", series: allSeries)) {
                AllCategoryCard(title: "All Series", icon: "tv.and.mediabox", count: allSeries.count)
            }
            .cardFocusable()

            // Alphabetical categories
            ForEach(cachedGroupedSeries, id: \.category) { group in
                NavigationLink(destination: SeriesCategoryDetailView(category: group.category, series: group.items)) {
                    CategoryBrowserCard(title: group.category, count: group.items.count,
                                        samplePosters: group.items.prefix(4).map(\.posterURL))
                }
                .cardFocusable()
            }
        }
        .padding(.horizontal)
    }

    private var lockedPlaceholder: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle().fill(Color.saAccent.opacity(0.1)).frame(width: 120, height: 120)
                Image(systemName: "tv.fill").font(.system(size: 48)).foregroundStyle(Color.saAccent)
            }
            Text("TV Series").font(.title.bold()).foregroundStyle(Color.saTextPrimary)
            Text("Unlock the full series section with StreamArc+")
                .font(.body).multilineTextAlignment(.center)
                .foregroundStyle(Color.saTextSecondary).padding(.horizontal, 40)
            Button("Upgrade to StreamArc+") { showPaywall = true }
                .buttonStyle(AccentButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).streamArcBackground()
    }

    private func loadTMDB() async {
        guard trendingTV.isEmpty, !apiKey.isEmpty else { return }
        trendingTV = (try? await TMDBClient.shared.trendingTV(timeWindow: "day", apiKey: apiKey)) ?? []
    }
}

// MARK: - Hero Carousel

private struct SeriesHeroCarousel: View {
    let items: [TMDBTrendingItem]
    @Binding var heroIndex: Int
    let onTap: (TMDBTrendingItem) -> Void

    private var hero: TMDBTrendingItem { items[heroIndex % items.count] }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let url = hero.backdropURL ?? hero.posterURL {
                    KFImage(url).resizable().placeholder { ShimmerCard() }
                        .fade(duration: 0.4).scaledToFill()
                } else { Rectangle().fill(Color.saSurface) }
            }
            .frame(maxWidth: .infinity).frame(height: bannerHeight).clipped()
            .animation(.easeInOut(duration: 0.5), value: heroIndex)

            LinearGradient(stops: [.init(color: .clear, location: 0.15),
                                   .init(color: Color.saBackground.opacity(0.7), location: 0.65),
                                   .init(color: Color.saBackground, location: 1)],
                           startPoint: .top, endPoint: .bottom)
            LinearGradient(colors: [Color.saBackground.opacity(0.4), .clear], startPoint: .leading, endPoint: .trailing)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 5) {
                    Image(systemName: "tv.fill").font(.caption.bold()).foregroundStyle(Color.saAccent)
                    Text("Featured Series").font(.caption.bold()).foregroundStyle(Color.saAccent)
                }
                Text(hero.displayTitle).font(.system(size: 26, weight: .heavy))
                    .foregroundStyle(.white).lineLimit(2)
                    .shadow(color: .black.opacity(0.5), radius: 6)

                // Year + Rating
                HStack(spacing: 8) {
                    if let year = hero.releaseYear {
                        Text(year).font(.caption.bold()).foregroundStyle(Color.saTextSecondary)
                    }
                    if let r = hero.voteAverage, r > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "star.fill").font(.system(size: 9)).foregroundStyle(.yellow)
                            Text(String(format: "%.1f", r)).font(.caption.bold()).foregroundStyle(.white)
                        }
                    }
                }

                if let ov = hero.overview, !ov.isEmpty {
                    Text(ov).font(.caption).foregroundStyle(.white.opacity(0.72)).lineLimit(2)
                }
                HStack(spacing: 12) {
                    Button { onTap(hero) } label: {
                        HStack(spacing: 6) { Image(systemName: "play.fill"); Text("Watch Now") }
                            .font(.subheadline.bold()).foregroundStyle(Color.saBackground)
                            .padding(.horizontal, 20).padding(.vertical, 11)
                            .background(.white).clipShape(Capsule())
                    }
                    .cardFocusable()
                    if let r = hero.voteAverage, r > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "star.fill").foregroundStyle(.yellow)
                            Text(String(format: "%.1f", r)).foregroundStyle(.white)
                        }
                        .font(.caption.bold()).padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Color.white.opacity(0.14)).clipShape(Capsule())
                    }
                    Spacer()
                    if items.count > 1 {
                        HStack(spacing: 5) {
                            ForEach(0..<items.count, id: \.self) { i in
                                Capsule()
                                    .fill(i == heroIndex % items.count ? Color.white : Color.white.opacity(0.3))
                                    .frame(width: i == heroIndex % items.count ? 18 : 6, height: 6)
                                    .animation(.spring(response: 0.3), value: heroIndex)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20).padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity).frame(height: bannerHeight)
        .task(id: items.count) {
            guard items.count > 1 else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_500_000_000)
                guard !Task.isCancelled else { return }
                heroIndex = (heroIndex + 1) % items.count
            }
        }
    }

    private var bannerHeight: CGFloat {
        #if os(tvOS)
        return 500
        #else
        return 340
        #endif
    }
}

// MARK: - Poster Cards

struct SeriesTMDBPosterCard: View {
    let item: TMDBTrendingItem
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ZStack(alignment: .topTrailing) {
                if let url = item.posterURL {
                    KFImage(url).resizable().placeholder { ShimmerCard() }.fade(duration: 0.25).scaledToFill()
                } else {
                    Rectangle().fill(Color.saSurface)
                        .overlay(Image(systemName: "tv.and.mediabox").font(.title2).foregroundStyle(Color.saTextSecondary.opacity(0.3)))
                }
                if let r = item.voteAverage, r > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "star.fill").font(.system(size: 8, weight: .bold)).foregroundStyle(.yellow)
                        Text(String(format: "%.1f", r)).font(.system(size: 9, weight: .heavy)).foregroundStyle(.white)
                    }
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(Color.black.opacity(0.72)).clipShape(Capsule()).padding(6)
                }
            }
            .aspectRatio(2/3, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.07), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.35), radius: 8, y: 4)

            Text(item.displayTitle)
                .font(.system(size: titleFontSize, weight: .semibold))
                .foregroundStyle(Color.saTextPrimary)
                .lineLimit(2)

            if let year = item.releaseYear {
                Text(year)
                    .font(.system(size: metaFontSize, weight: .medium))
                    .foregroundStyle(Color.saTextSecondary)
            }
        }
        .frame(width: cardWidth)
    }

    private var cardWidth: CGFloat {
        #if os(tvOS)
        return 180
        #elseif os(macOS)
        return 150
        #else
        return 120
        #endif
    }
    private var titleFontSize: CGFloat {
        #if os(tvOS)
        return 14
        #else
        return 11
        #endif
    }
    private var metaFontSize: CGFloat {
        #if os(tvOS)
        return 12
        #else
        return 10
        #endif
    }
}

struct SeriesIPTVPosterCard: View {
    let series: Series
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            // Poster image — clean, title shown below
            Group {
                if let u = series.posterURL, let url = URL(string: u) {
                    KFImage(url).resizable().placeholder { ShimmerCard() }.fade(duration: 0.25).scaledToFill()
                } else {
                    Rectangle().fill(Color.saSurface)
                        .overlay { Image(systemName: "tv.and.mediabox").font(.title2)
                            .foregroundStyle(Color.saTextSecondary.opacity(0.3)) }
                }
            }
            .aspectRatio(2/3, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.07), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.3), radius: 6, y: 3)

            // Title below poster
            Text(series.title)
                .font(.system(size: titleFontSize, weight: .semibold))
                .foregroundStyle(Color.saTextPrimary)
                .lineLimit(2)

            // Genre tag
            if let genre = series.groupTitle, !genre.isEmpty {
                Text(genre)
                    .font(.system(size: metaFontSize, weight: .medium))
                    .foregroundStyle(Color.saAccent)
                    .lineLimit(1)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.saAccent.opacity(0.12))
                    .clipShape(Capsule())
            }
        }
        .frame(width: cardWidth)
    }

    private var cardWidth: CGFloat {
        #if os(tvOS)
        return 180
        #elseif os(macOS)
        return 150
        #else
        return 120
        #endif
    }
    private var titleFontSize: CGFloat {
        #if os(tvOS)
        return 14
        #else
        return 11
        #endif
    }
    private var metaFontSize: CGFloat {
        #if os(tvOS)
        return 11
        #else
        return 9
        #endif
    }
}

// MARK: - TMDB Discovery Sheet (Series)

private struct SeriesTMDBDiscoverySheet: View {
    let item: TMDBTrendingItem
    let seriesLibrary: [Series]
    var onMatchFound: (Series) -> Void
    @Environment(\.dismiss) private var dismiss

    private var match: Series? {
        seriesLibrary.first {
            $0.title.localizedCaseInsensitiveContains(item.displayTitle) ||
            item.displayTitle.localizedCaseInsensitiveContains($0.title)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let url = item.backdropURL ?? item.posterURL {
                        KFImage(url).resizable().scaledToFill()
                            .frame(maxWidth: .infinity).frame(height: 200).clipped()
                            .overlay(LinearGradient(colors: [.clear, Color.saBackground],
                                                    startPoint: .center, endPoint: .bottom))
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Text(item.displayTitle).font(.title2.bold()).foregroundStyle(Color.saTextPrimary)
                        HStack(spacing: 12) {
                            if let r = item.voteAverage, r > 0 {
                                Label(String(format: "%.1f", r), systemImage: "star.fill")
                                    .foregroundStyle(.yellow).font(.subheadline)
                            }
                            if let y = item.yearString { Text(y).foregroundStyle(Color.saTextSecondary).font(.subheadline) }
                        }
                        if let ov = item.overview { Text(ov).font(.body).foregroundStyle(Color.saTextSecondary) }
                        if let s = match {
                            Button { dismiss(); onMatchFound(s) } label: {
                                Label("Watch in Your Library", systemImage: "play.circle.fill")
                                    .font(.headline).frame(maxWidth: .infinity).padding()
                                    .background(Color.saAccent).foregroundStyle(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                            }.buttonStyle(.plain)
                        } else {
                            Label("Not in your library", systemImage: "xmark.circle")
                                .foregroundStyle(Color.saTextSecondary).font(.subheadline)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .background(Color.saBackground.ignoresSafeArea())
            .navigationTitle(item.displayTitle)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }
    }
}
