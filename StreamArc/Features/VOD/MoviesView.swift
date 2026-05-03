import StreamArcCore
import SwiftUI
import SwiftData
import Kingfisher

// MARK: - MoviesView

struct MoviesView: View {

    var viewModel: HomeViewModel

    @Environment(AppEnvironment.self)     private var appEnv
    @Environment(EntitlementManager.self) private var entitlements

    @State private var selectedItem: VODItem?
    @State private var showPaywall = false
    @State private var trendingMovies: [TMDBTrendingItem] = []
    @State private var nowInTheatres: [TMDBTrendingItem] = []
    @State private var selectedTMDB: TMDBTrendingItem?
    @State private var heroIndex: Int = 0
    @State private var cachedGroupedMovies: [(category: String, items: [VODItem])] = []
    @State private var allMovies: [VODItem] = []

    // Resume from Continue Watching
    @State private var resumeItem: VODItem?
    @State private var resumePosition: Double = 0

    @Query(sort: \FavoriteItem.addedAt, order: .reverse) private var favoriteItems: [FavoriteItem]

    private var apiKey: String {
        appEnv.settingsStore.tmdbAPIKey.isEmpty ? APIKeys.tmdb : appEnv.settingsStore.tmdbAPIKey
    }
    private var heroItems: [TMDBTrendingItem] { Array(trendingMovies.prefix(6)) }

    private var recentlyAdded: [VODItem] {
        Array(viewModel.vodItems.filter { $0.type == .movie }.suffix(9).reversed())
    }
    private var favoriteMovies: [VODItem] {
        let ids = Set(favoriteItems.filter { $0.contentType == "vod" }.map(\.contentId))
        return viewModel.vodItems.filter { ids.contains($0.id) }
    }
    /// Now In Theatres: TMDB items that have a match in the library
    private var nowInTheatresInLibrary: [TMDBTrendingItem] {
        nowInTheatres.filter { item in
            viewModel.vodItems.contains {
                $0.type == .movie && (
                    $0.title.localizedCaseInsensitiveContains(item.displayTitle) ||
                    item.displayTitle.localizedCaseInsensitiveContains($0.title)
                )
            }
        }
    }

    private func rebuildCache() {
        let all = viewModel.vodItems
        let isPremium = entitlements.isPremium
        Task.detached(priority: .userInitiated) {
            var movies = all.filter { $0.type == .movie }
            if !isPremium { movies = Array(movies.prefix(50)) }
            var dict: [String: [VODItem]] = [:]
            for m in movies {
                let key = m.groupTitle.isEmpty ? "Uncategorized" : m.groupTitle
                dict[key, default: []].append(m)
            }
            // Sort alphabetically
            let keys = dict.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            let grouped = keys.map { (category: $0, items: dict[$0]!) }
            await MainActor.run {
                self.allMovies = movies
                self.cachedGroupedMovies = grouped
            }
        }
    }

    var body: some View {
        ZStack {
            Color.saBackground.ignoresSafeArea()
            switch viewModel.loadState {
            case .idle, .loading:
                ScrollView { ShimmerGrid(columns: 3).padding(.top, 20) }
            case .error(let msg):
                ErrorView(message: msg)
            case .loaded:
                mainContent
            }
        }
        .task {
            if case .loaded = viewModel.loadState { rebuildCache() }
            await loadTMDB()
        }
        .onChange(of: viewModel.loadState) { _, s in if case .loaded = s { rebuildCache() } }
        .onChange(of: entitlements.isPremium) { _, _ in rebuildCache() }
        #if os(macOS)
        .sheet(item: $selectedItem) { MovieDetailView(item: $0) }
        .sheet(item: $selectedTMDB) { i in TMDBDiscoverySheet(item: i, vodItems: viewModel.vodItems) { selectedItem = $0 } }
        .sheet(item: $resumeItem) { item in
            PlayerView(streamURL: item.streamURL, title: item.title, startPosition: resumePosition,
                       contentId: item.id, posterURL: item.posterURL, historyContentType: "vod")
        }
        #else
        .fullScreenCover(item: $selectedItem) { MovieDetailView(item: $0) }
        .sheet(item: $selectedTMDB) { i in TMDBDiscoverySheet(item: i, vodItems: viewModel.vodItems) { selectedItem = $0 } }
        .fullScreenCover(item: $resumeItem) { item in
            PlayerView(streamURL: item.streamURL, title: item.title, startPosition: resumePosition,
                       contentId: item.id, posterURL: item.posterURL, historyContentType: "vod")
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
                    MoviesHeroCarousel(items: heroItems, heroIndex: $heroIndex) { selectedTMDB = $0 }
                        .padding(.bottom, 28)
                }

                // 2. Continue Watching
                ContinueWatchingRow { entry, _ in
                    if let match = viewModel.vodItems.first(where: { $0.id == entry.contentId }) {
                        resumePosition = entry.lastPosition
                        resumeItem = match
                    }
                }
                .padding(.bottom, 4)

                // 3. Favourites
                if !favoriteMovies.isEmpty {
                    PlexShelfSection(title: "My Favourites", icon: "star.fill", iconColor: .yellow) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(alignment: .top, spacing: 10) {
                                ForEach(favoriteMovies) { item in
                                    Button { selectedItem = item } label: { MovieIPTVPosterCard(item: item) }
                                        .cardFocusable()
                                }
                            }
                            .padding(.horizontal).padding(.vertical, 4)
                        }
                    }
                    .padding(.bottom, 28)
                }

                // 4. Trending Now
                if !trendingMovies.isEmpty {
                    PlexShelfSection(title: "Trending Now", icon: "flame.fill", iconColor: .orange) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(alignment: .top, spacing: 10) {
                                ForEach(trendingMovies) { item in
                                    Button { selectedTMDB = item } label: { MovieTMDBPosterCard(item: item) }
                                        .cardFocusable()
                                }
                            }
                            .padding(.horizontal).padding(.vertical, 4)
                        }
                    }
                    .padding(.bottom, 28)
                }

                // 5. Now In Theatres (library matches only)
                if !nowInTheatresInLibrary.isEmpty {
                    PlexShelfSection(title: "Now In Theatres", icon: "popcorn.fill", iconColor: .red) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(alignment: .top, spacing: 10) {
                                ForEach(nowInTheatresInLibrary) { item in
                                    Button { selectedTMDB = item } label: { MovieTMDBPosterCard(item: item) }
                                        .cardFocusable()
                                }
                            }
                            .padding(.horizontal).padding(.vertical, 4)
                        }
                    }
                    .padding(.bottom, 28)
                }

                // 6. Recently Added
                if !recentlyAdded.isEmpty {
                    PlexShelfSection(title: "Recently Added", icon: "clock.fill", iconColor: .blue) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(alignment: .top, spacing: 10) {
                                ForEach(recentlyAdded) { item in
                                    Button { selectedItem = item } label: { MovieIPTVPosterCard(item: item) }
                                        .cardFocusable()
                                }
                            }
                            .padding(.horizontal).padding(.vertical, 4)
                        }
                    }
                    .padding(.bottom, 28)
                }

                // 7. Your Library (All first, then alphabetical categories)
                if !cachedGroupedMovies.isEmpty || !allMovies.isEmpty {
                    PlexShelfSection(title: "Your Library", icon: "square.grid.2x2.fill", iconColor: Color.saAccent) {
                        EmptyView()
                    }
                    categoryBrowserGrid.padding(.bottom, 28)
                } else if viewModel.vodItems.isEmpty {
                    EmptyContentView(title: "No Movies Found",
                                     subtitle: "Your source didn't return any movies.",
                                     systemImage: "film.fill")
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
            // "All Movies" card — always first
            NavigationLink(destination: MovieCategoryDetailView(category: "All Movies", movies: allMovies)) {
                AllCategoryCard(title: "All Movies", icon: "film.fill", count: allMovies.count)
            }
            .cardFocusable()

            // Alphabetical categories
            ForEach(cachedGroupedMovies, id: \.category) { group in
                NavigationLink(destination: MovieCategoryDetailView(category: group.category, movies: group.items)) {
                    CategoryBrowserCard(title: group.category, count: group.items.count,
                                        samplePosters: group.items.prefix(4).map(\.posterURL))
                }
                .cardFocusable()
            }
        }
        .padding(.horizontal)
    }

    private func loadTMDB() async {
        guard !apiKey.isEmpty else { return }
        async let trending = (try? await TMDBClient.shared.trendingMovies(apiKey: apiKey)) ?? []
        async let theatres = (try? await TMDBClient.shared.nowPlayingMovies(apiKey: apiKey)) ?? []
        let (t, n) = await (trending, theatres)
        if trendingMovies.isEmpty { trendingMovies = t }
        if nowInTheatres.isEmpty  { nowInTheatres = n }
    }
}

// MARK: - Hero Carousel

private struct MoviesHeroCarousel: View {
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
                    Image(systemName: "sparkles").font(.caption.bold()).foregroundStyle(Color.saAccent)
                    Text("Featured").font(.caption.bold()).foregroundStyle(Color.saAccent)
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
            .padding(.horizontal, hEdge).padding(.bottom, 20)
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

    private var hEdge: CGFloat { 20 }

    private var bannerHeight: CGFloat {
        #if os(tvOS)
        return 500
        #else
        return 340
        #endif
    }
}

// MARK: - All Category Card

struct AllCategoryCard: View {
    let title: String
    let icon: String
    let count: Int

    @Environment(\.isFocused) private var isFocused

    private let gradient = LinearGradient(
        colors: [Color.saAccent.opacity(0.9), Color.saAccent.opacity(0.5)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Card face — coloured background with icon
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(gradient)
                    .aspectRatio(16/9, contentMode: .fit)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(isFocused ? Color.white.opacity(0.6) : Color.white.opacity(0.15), lineWidth: 1.5)
                    )
                VStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            // Count label
            Text("\(count) \(count == 1 ? "title" : "titles")")
                .font(.system(size: 12))
                .foregroundStyle(Color.saTextSecondary)
        }
        .padding(.bottom, 4)
    }
}

// MARK: - Poster Cards (shared)

struct MovieTMDBPosterCard: View {
    let item: TMDBTrendingItem
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ZStack(alignment: .topTrailing) {
                if let url = item.posterURL {
                    KFImage(url).resizable().placeholder { ShimmerCard() }.fade(duration: 0.25).scaledToFill()
                } else {
                    Rectangle().fill(Color.saSurface)
                        .overlay(Image(systemName: "film").font(.title2).foregroundStyle(Color.saTextSecondary.opacity(0.3)))
                }
                // Rating badge top-right
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

            // Title below poster - clearly visible
            Text(item.displayTitle)
                .font(.system(size: titleFontSize, weight: .semibold))
                .foregroundStyle(Color.saTextPrimary)
                .lineLimit(2)

            // Year below title
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

struct MovieIPTVPosterCard: View {
    let item: VODItem
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            // Poster image — clean, no title overlay
            Group {
                if let u = item.posterURL, let url = URL(string: u) {
                    KFImage(url).resizable().placeholder { ShimmerCard() }.fade(duration: 0.25).scaledToFill()
                } else {
                    Rectangle().fill(Color.saSurface)
                        .overlay { Image(systemName: "film").font(.title2).foregroundStyle(Color.saTextSecondary.opacity(0.3)) }
                }
            }
            .aspectRatio(2/3, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.07), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.3), radius: 6, y: 3)

            // Title below poster — clearly readable
            Text(item.title)
                .font(.system(size: titleFontSize, weight: .semibold))
                .foregroundStyle(Color.saTextPrimary)
                .lineLimit(2)

            // Genre tag
            if !item.groupTitle.isEmpty {
                Text(item.groupTitle)
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

// MARK: - TMDB Discovery Sheet

struct TMDBDiscoverySheet: View {
    let item: TMDBTrendingItem
    let vodItems: [VODItem]
    var onMatchFound: (VODItem) -> Void
    @Environment(\.dismiss) private var dismiss

    private var match: VODItem? {
        vodItems.first {
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
                        if let v = match {
                            Button { dismiss(); onMatchFound(v) } label: {
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
