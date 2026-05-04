import StreamArcCore
import SwiftUI
import SwiftData
import Kingfisher

// ContentRootView: routes between onboarding and the main UI.
struct ContentRootView: View {
    @Query private var profiles: [Profile]
    @Environment(AppEnvironment.self) private var appEnv

    @State private var showSourcePicker = false

    var body: some View {
        Group {
            if profiles.isEmpty {
                OnboardingView()
            } else {
                HomeView()
            }
        }
        .sheet(isPresented: $showSourcePicker) {
            SourcePickerView(profiles: profiles) { _ in
                showSourcePicker = false
            }
            #if os(iOS)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            #endif
        }
        .task {
            if profiles.count > 1 {
                showSourcePicker = true
            }
        }
    }
}

// MARK: - HomeView

struct HomeView: View {

    @Query(filter: #Predicate<Profile> { $0.isActive == true })
    private var activeProfiles: [Profile]

    @Query private var allProfiles: [Profile]

    @State private var viewModel = HomeViewModel()
    @State private var selectedTab: Tab = .home
    @State private var showAddProfile = false

    @Environment(AdsManager.self)          private var adsManager
    @Environment(InterstitialAdManager.self) private var interstitialManager

    enum Tab: Int, CaseIterable {
        case home, liveTV, movies, series, settings, search, epg

        /// Tabs displayed in the iOS tab bar — max 5, Home-first for thumb reach.
        /// Search is surfaced via .searchable toolbar; EPG lives inside Live TV.
        static var iOSTabs: [Tab] { [.home, .liveTV, .movies, .series, .settings] }

        /// All tabs for macOS sidebar and tvOS TabView.
        static var allDisplayTabs: [Tab] { [.home, .liveTV, .movies, .series, .search, .epg, .settings] }

        var title: String {
            switch self {
            case .home: "Home"; case .movies: "Movies"; case .series: "Series"
            case .liveTV: "TV"; case .epg: "EPG"; case .search: "Search"; case .settings: "Settings"
            }
        }
        var systemImage: String {
            switch self {
            case .home: "house.fill"; case .movies: "film"; case .series: "tv.and.mediabox"
            case .liveTV: "tv"; case .epg: "calendar"; case .search: "magnifyingglass"
            case .settings: "gearshape"
            }
        }
    }

    var activeProfile: Profile? { activeProfiles.first }

    var body: some View {
#if os(macOS)
        macLayout
#elseif os(tvOS)
        tvLayout
#else
        iOSLayout
#endif
    }

    // MARK: - iOS / iPadOS layout

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var hSizeClass

    private var iOSLayout: some View {
        ZStack {
            // iPad (regular width) → NavigationSplitView with sidebar
            // iPhone (compact width) → 5-tab TabView
            if hSizeClass == .regular {
                iPadLayout
            } else {
                iPhoneTabView
            }

            if viewModel.loadState == .loading {
                SplashScreenView(progress: viewModel.loadProgress, status: viewModel.loadStatus)
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.5), value: viewModel.loadState == .loading)
            }
        }
        .tint(Color.saAccent)
        .streamArcBackground()
        .onChange(of: selectedTab) { _, _ in interstitialManager.recordTabSwitch() }
        .task(id: activeProfile?.id) {
            if let profile = activeProfile { await viewModel.load(profile: profile) }
            else { viewModel.noActiveProfile() }
        }
    }

    /// iPhone: compact 5-tab TabView. Home first. Search exposed via .searchable on content views.
    private var iPhoneTabView: some View {
        TabView(selection: $selectedTab) {
            ForEach(Tab.iOSTabs, id: \.self) { tab in
                tabContent(tab)
                    .tabItem { Label(tab.title, systemImage: tab.systemImage) }
                    .tag(tab)
            }
        }
    }

    /// iPad: NavigationSplitView — sidebar list + main content area.
    private var iPadLayout: some View {
        NavigationSplitView(columnVisibility: .constant(.doubleColumn)) {
            List(Tab.allDisplayTabs, id: \.self) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    Label(tab.title, systemImage: tab.systemImage)
                        .foregroundStyle(selectedTab == tab ? Color.saAccent : Color.saTextPrimary)
                        .fontWeight(selectedTab == tab ? .semibold : .regular)
                }
                .listRowBackground(selectedTab == tab ? Color.saAccent.opacity(0.12) : Color.clear)
            }
            .listStyle(.sidebar)
            .navigationTitle("StreamArc")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    profileToolbarButton
                }
            }
        } detail: {
            tabContent(selectedTab)
        }
        .navigationSplitViewStyle(.balanced)
    }

    @ViewBuilder
    private var profileToolbarButton: some View {
        if let profile = activeProfile {
            Menu {
                ForEach(allProfiles) { p in
                    Button {
                        for pr in allProfiles { pr.isActive = false }
                        p.isActive = true
                    } label: {
                        Label(p.name, systemImage: p.isActive ? "checkmark.circle.fill" : "circle")
                    }
                }
                Divider()
                Button("Add Profile", systemImage: "plus") { showAddProfile = true }
            } label: {
                Label(profile.name, systemImage: "person.circle")
                    .labelStyle(.iconOnly)
            }
        }
    }
    #endif

    // MARK: - tvOS layout

    #if os(tvOS)
    private var tvLayout: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                ForEach(Tab.allDisplayTabs, id: \.self) { tab in
                    tabContent(tab)
                        .tabItem { Label(tab.title, systemImage: tab.systemImage) }
                        .tag(tab)
                }
            }
            .task(id: activeProfile?.id) {
                if let profile = activeProfile { await viewModel.load(profile: profile) }
                else { viewModel.noActiveProfile() }
            }
            if viewModel.loadState == .loading {
                SplashScreenView(progress: viewModel.loadProgress, status: viewModel.loadStatus)
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.5), value: viewModel.loadState == .loading)
            }
        }
    }
    #endif

    // MARK: - macOS layout

    #if os(macOS)
    private var macLayout: some View {
        NavigationSplitView {
            List(Tab.allDisplayTabs, id: \.self, selection: $selectedTab) { tab in
                Label(tab.title, systemImage: tab.systemImage)
                    .tag(tab)
            }
            .listStyle(.sidebar)
            .navigationTitle("StreamArc")
        } detail: {
            ZStack {
                tabContent(selectedTab)
                if viewModel.loadState == .loading {
                    SplashScreenView(progress: viewModel.loadProgress, status: viewModel.loadStatus)
                        .transition(.opacity)
                        .animation(.easeInOut(duration: 0.5), value: viewModel.loadState == .loading)
                }
            }
        }
        .task(id: activeProfile?.id) {
            if let profile = activeProfile {
                await viewModel.load(profile: profile)
            } else {
                viewModel.noActiveProfile()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .switchToTab)) { notification in
            if let tab = notification.object as? Tab {
                selectedTab = tab
            }
        }
    }
    #endif

    // MARK: - Tab content

    @ViewBuilder
    private func tabContent(_ tab: Tab) -> some View {
        switch tab {
        case .search:
            SearchView(viewModel: viewModel)
        case .home:
            DashboardView(viewModel: viewModel)
        case .movies:
            MoviesView(viewModel: viewModel)
        case .series:
            SeriesView(viewModel: viewModel)
        case .liveTV:
            LiveTVView(viewModel: viewModel)
        case .epg:
            EPGTabView(viewModel: viewModel)
        case .settings:
            SettingsView()
        }
    }
}

// MARK: - Splash Screen

struct SplashScreenView: View {
    let progress: Double
    let status: String

    var body: some View {
        ZStack {
            Color.saBackground.ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                Image("AppLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 110, height: 110)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .shadow(color: Color.saAccent.opacity(0.45), radius: 24, y: 8)

                Text("StreamArc")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Spacer()

                VStack(spacing: 12) {
                    Text(status)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Color.saTextSecondary)
                        .multilineTextAlignment(.center)
                        .animation(.easeInOut, value: status)

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.1))
                                .frame(height: 5)
                            Capsule()
                                .fill(LinearGradient(
                                    colors: [Color.saAccent, Color.saAccent.opacity(0.6)],
                                    startPoint: .leading, endPoint: .trailing))
                                .frame(width: max(0, geo.size.width * progress), height: 5)
                                .animation(.easeInOut(duration: 0.5), value: progress)
                        }
                    }
                    .frame(height: 5)
                }
                .padding(.horizontal, 48)
                .padding(.bottom, 56)
            }
        }
    }
}

// MARK: - Dashboard (Home tab)

struct DashboardView: View {
    var viewModel: HomeViewModel

    @Environment(AppEnvironment.self) private var appEnv
    @Environment(\.modelContext) private var modelContext
    @State private var trendingMovies: [TMDBTrendingItem] = []
    @State private var trendingTV:    [TMDBTrendingItem] = []
    @State private var heroIndex: Int = 0
    @State private var selectedVOD: VODItem?
    @State private var selectedSeries: Series?
    @State private var selectedChannel: Channel?
    @State private var showChannelPlayer = false
    @State private var resumeEpisode: (streamURL: String, title: String, posterURL: String?, position: Double)?
    @State private var resumeVOD: VODItem?
    @State private var resumeVODPosition: Double = 0

    @Query(filter: #Predicate<Profile> { $0.isActive == true })
    private var activeProfiles: [Profile]
    @Query private var allProfiles: [Profile]
    @State private var showAddProfile = false

    private var activeProfile: Profile? { activeProfiles.first }

    private var apiKey: String {
        appEnv.settingsStore.tmdbAPIKey.isEmpty ? APIKeys.tmdb : appEnv.settingsStore.tmdbAPIKey
    }

    private var heroItems: [TMDBTrendingItem] {
        Array((trendingMovies + trendingTV).prefix(6))
    }

    private var liveNowChannels: [Channel] {
        viewModel.channels.filter { $0.currentProgram != nil }.prefix(20).map { $0 }
    }

    // MARK: - Tap handlers

    /// Open detail for a TMDB trending movie.
    /// If the title matches a library VODItem, use it (preserves streamURL).
    /// Otherwise create a TMDB-only stub so MovieDetailView still shows metadata.
    private func openMovie(_ item: TMDBTrendingItem) {
        if let v = viewModel.vodItems.first(where: {
            $0.title.localizedCaseInsensitiveContains(item.displayTitle) ||
            item.displayTitle.localizedCaseInsensitiveContains($0.title)
        }) {
            selectedVOD = v
        } else {
            // No library match — create TMDB stub (tmdbId allows fetchDetail to work)
            selectedVOD = VODItem(
                id: "tmdb-\(item.id)",
                title: item.displayTitle,
                posterURL: item.posterURL?.absoluteString,
                streamURL: "",
                tmdbId: item.id,
                type: .movie
            )
        }
    }

    /// Open detail for a TMDB trending TV show.
    private func openTV(_ item: TMDBTrendingItem) {
        if let s = viewModel.series.first(where: {
            $0.title.localizedCaseInsensitiveContains(item.displayTitle) ||
            item.displayTitle.localizedCaseInsensitiveContains($0.title)
        }) {
            selectedSeries = s
        } else {
            // No library match — show as movie detail (TMDB-only stub, type=.series for TV metadata)
            selectedVOD = VODItem(
                id: "tmdb-\(item.id)",
                title: item.displayTitle,
                posterURL: item.posterURL?.absoluteString,
                streamURL: "",
                tmdbId: item.id,
                type: .series
            )
        }
    }

    // MARK: - Profile switcher (iOS toolbar)

    @ViewBuilder
    private var profileMenuButton: some View {
        #if os(iOS)
        Menu {
            ForEach(allProfiles) { p in
                Button {
                    for pr in allProfiles { pr.isActive = false }
                    p.isActive = true
                    try? modelContext.save()
                } label: {
                    Label(p.name, systemImage: p.isActive ? "checkmark.circle.fill" : "circle")
                }
            }
            Divider()
            Button("Add Profile", systemImage: "plus") { showAddProfile = true }
        } label: {
            Image(systemName: "person.circle").font(.body.weight(.medium))
        }
        #endif
    }

    // MARK: - Shelf content (shared between tvOS and iOS paths)

    @ViewBuilder private var heroSection: some View {
        if !heroItems.isEmpty {
            DashboardHero(items: heroItems, heroIndex: $heroIndex) { item in
                if item.mediaType == "tv" { openTV(item) } else { openMovie(item) }
            }
            .padding(.bottom, 28)
            #if os(tvOS)
            .focusSection()
            #endif
        }
    }

    @ViewBuilder private var continueWatchingSection: some View {
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
            } else if entry.contentType == "vod" {
                if let match = viewModel.vodItems.first(where: { $0.id == entry.contentId }) {
                    resumeVODPosition = entry.lastPosition; resumeVOD = match
                }
            }
        }
        .padding(.bottom, 28)
        #if os(tvOS)
        .focusSection()
        #endif
    }

    @ViewBuilder private var liveNowSection: some View {
        if !liveNowChannels.isEmpty {
            PlexShelfSection(title: "Live Now", icon: "dot.radiowaves.left.and.right", iconColor: .red) {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(liveNowChannels) { ch in
                            Button { selectedChannel = ch; showChannelPlayer = true } label: { LiveNowCard(channel: ch) }
                            .cardFocusable()
                        }
                    }
                    .padding(.horizontal).padding(.vertical, 4)
                }
            }
            .padding(.bottom, 28)
            #if os(tvOS)
            .focusSection()
            #endif
        }
    }

    @ViewBuilder private var trendingMoviesSection: some View {
        if !trendingMovies.isEmpty {
            PlexShelfSection(title: "Trending Movies", icon: "flame.fill", iconColor: .orange) {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 10) {
                        ForEach(trendingMovies) { item in
                            Button { openMovie(item) } label: { MovieTMDBPosterCard(item: item) }
                            .cardFocusable()
                        }
                    }
                    .padding(.horizontal).padding(.vertical, 4)
                }
            }
            .padding(.bottom, 28)
            #if os(tvOS)
            .focusSection()
            #endif
        }
    }

    @ViewBuilder private var trendingTVSection: some View {
        if !trendingTV.isEmpty {
            PlexShelfSection(title: "Trending TV Shows", icon: "tv.fill", iconColor: .blue) {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 10) {
                        ForEach(trendingTV) { item in
                            Button { openTV(item) } label: { SeriesTMDBPosterCard(item: item) }
                            .cardFocusable()
                        }
                    }
                    .padding(.horizontal).padding(.vertical, 4)
                }
            }
            .padding(.bottom, 28)
            #if os(tvOS)
            .focusSection()
            #endif
        }
    }

    // MARK: - Main body

    var body: some View {
        mainContent
            .task { await loadTrending() }
            // tvOS: full-screen covers
            #if os(tvOS)
            .fullScreenCover(item: $selectedVOD) { MovieDetailView(item: $0) }
            .fullScreenCover(item: $selectedSeries) { SeriesDetailView(series: $0) }
            .fullScreenCover(isPresented: $showChannelPlayer) {
                if let ch = selectedChannel {
                    PlayerView(streamURL: ch.streamURL, title: ch.name,
                               posterURL: ch.logoURL, isLiveTV: true,
                               channel: ch, allChannels: viewModel.channels)
                }
            }
            .fullScreenCover(isPresented: Binding(
                get: { resumeEpisode != nil }, set: { if !$0 { resumeEpisode = nil } }
            )) {
                if let ep = resumeEpisode {
                    PlayerView(streamURL: ep.streamURL, title: ep.title,
                               posterURL: ep.posterURL, contentType: "episode", startPosition: ep.position)
                }
            }
            .fullScreenCover(item: $resumeVOD) { item in
                PlayerView(streamURL: item.streamURL, title: item.title,
                           posterURL: item.posterURL, contentType: "vod",
                           startPosition: resumeVODPosition, contentId: item.id)
            }
            // macOS: sheets
            #elseif os(macOS)
            .sheet(item: $selectedVOD) { MovieDetailView(item: $0) }
            .sheet(item: $selectedSeries) { SeriesDetailView(series: $0) }
            .sheet(item: $resumeVOD) { item in
                PlayerView(streamURL: item.streamURL, title: item.title,
                           posterURL: item.posterURL, contentType: "vod",
                           startPosition: resumeVODPosition, contentId: item.id)
            }
            .sheet(isPresented: Binding(
                get: { resumeEpisode != nil }, set: { if !$0 { resumeEpisode = nil } }
            )) {
                if let ep = resumeEpisode {
                    PlayerView(streamURL: ep.streamURL, title: ep.title,
                               posterURL: ep.posterURL, contentType: "episode", startPosition: ep.position)
                }
            }
            .sheet(isPresented: $showChannelPlayer) {
                if let ch = selectedChannel {
                    PlayerView(streamURL: ch.streamURL, title: ch.name,
                               posterURL: ch.logoURL, isLiveTV: true,
                               channel: ch, allChannels: viewModel.channels)
                }
            }
            // iOS: full-screen covers
            #else
            .sheet(item: $selectedVOD) { MovieDetailView(item: $0) }
            .sheet(item: $selectedSeries) { SeriesDetailView(series: $0) }
            .sheet(item: $resumeVOD) { item in
                PlayerView(streamURL: item.streamURL, title: item.title,
                           posterURL: item.posterURL, contentType: "vod",
                           startPosition: resumeVODPosition, contentId: item.id)
            }
            .fullScreenCover(isPresented: Binding(
                get: { resumeEpisode != nil }, set: { if !$0 { resumeEpisode = nil } }
            )) {
                if let ep = resumeEpisode {
                    PlayerView(streamURL: ep.streamURL, title: ep.title,
                               posterURL: ep.posterURL, contentType: "episode", startPosition: ep.position)
                }
            }
            .fullScreenCover(isPresented: $showChannelPlayer) {
                if let ch = selectedChannel {
                    PlayerView(streamURL: ch.streamURL, title: ch.name,
                               posterURL: ch.logoURL, isLiveTV: true,
                               channel: ch, allChannels: viewModel.channels)
                }
            }
            #endif
    }

    // MARK: - Platform-split main content

    @ViewBuilder
    private var mainContent: some View {
        #if os(tvOS)
        // tvOS: NO NavigationStack — TabView already provides the navigation context.
        // NavigationStack inside tvOS TabView adds unwanted chrome.
        ZStack {
            Color.saBackground.ignoresSafeArea()
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    heroSection
                    continueWatchingSection
                    liveNowSection
                    trendingMoviesSection
                    trendingTVSection
                    Spacer(minLength: 60)
                }
            }
        }
        #else
        NavigationStack {
            ZStack {
                Color.saBackground.ignoresSafeArea()
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        heroSection
                        continueWatchingSection
                        liveNowSection
                        trendingMoviesSection
                        trendingTVSection
                        Spacer(minLength: 60)
                    }
                }
            }
            .background(Color.saBackground.ignoresSafeArea())
            .navigationTitle("Home")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { profileMenuButton } }
            #endif
        }
        #endif
    }

    private func loadTrending() async {
        guard trendingMovies.isEmpty, !apiKey.isEmpty else { return }
        async let m = (try? await TMDBClient.shared.trendingMovies(apiKey: apiKey)) ?? []
        async let t = (try? await TMDBClient.shared.trendingTV(apiKey: apiKey)) ?? []
        let (movies, tv) = await (m, t)
        trendingMovies = Array(movies.prefix(9))
        trendingTV     = Array(tv.prefix(8))
    }
}


// MARK: - Dashboard Hero

private struct DashboardHero: View {
    let items: [TMDBTrendingItem]
    @Binding var heroIndex: Int
    let onTap: (TMDBTrendingItem) -> Void

    private var hero: TMDBTrendingItem { items[heroIndex % items.count] }

    private var bannerHeight: CGFloat {
        #if os(tvOS)
        return 520
        #else
        return 340
        #endif
    }

    private var titleFont: Font {
        #if os(tvOS)
        return .system(size: 48, weight: .heavy)
        #else
        return .system(size: 26, weight: .heavy)
        #endif
    }

    private var hPad: CGFloat {
        #if os(tvOS)
        return 60
        #else
        return 20
        #endif
    }

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
                                   .init(color: Color.saBackground.opacity(0.65), location: 0.6),
                                   .init(color: Color.saBackground, location: 1)],
                           startPoint: .top, endPoint: .bottom)
            // Side gradient for readability
            LinearGradient(colors: [Color.saBackground.opacity(0.45), .clear],
                           startPoint: .leading, endPoint: .trailing)

            VStack(alignment: .leading, spacing: 12) {
                // Featured badge
                HStack(spacing: 5) {
                    Image(systemName: "sparkles").font(.caption.bold()).foregroundStyle(Color.saAccent)
                    Text("Featured").font(.caption.bold()).foregroundStyle(Color.saAccent)
                }

                // Title
                Text(hero.displayTitle)
                    .font(titleFont)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .shadow(color: .black.opacity(0.5), radius: 6)

                // Year + Genre metadata row
                HStack(spacing: 8) {
                    if let year = hero.releaseYear {
                        Text(year)
                            .font(.caption.bold())
                            .foregroundStyle(Color.saTextSecondary)
                    }
                    if let r = hero.voteAverage, r > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "star.fill").font(.system(size: 9, weight: .bold)).foregroundStyle(.yellow)
                            Text(String(format: "%.1f", r)).font(.caption.bold()).foregroundStyle(.white)
                        }
                    }
                }

                // Overview (brief)
                if let overview = hero.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(2)
                        .shadow(color: .black.opacity(0.4), radius: 4)
                }

                HStack(spacing: 12) {
                    Button { onTap(hero) } label: {
                        HStack(spacing: 6) { Image(systemName: "play.fill"); Text("Watch Now") }
                            #if os(tvOS)
                            .font(.system(size: 20, weight: .bold))
                            .padding(.horizontal, 32).padding(.vertical, 16)
                            #else
                            .font(.subheadline.bold())
                            .padding(.horizontal, 20).padding(.vertical, 11)
                            #endif
                            .foregroundStyle(Color.saBackground)
                            .background(.white).clipShape(Capsule())
                    }
                    .cardFocusable()

                    Spacer()

                    // Page dots
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
            .padding(.horizontal, hPad)
            #if os(tvOS)
            .padding(.bottom, 50)
            #else
            .padding(.bottom, 24)
            #endif
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
}

// MARK: - Live Now Card

private struct LiveNowCard: View {
    let channel: Channel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.saSurface)
                if let url = channel.logoURL.flatMap(URL.init) {
                    KFImage(url).resizable().scaledToFit().padding(10)
                } else {
                    Image(systemName: "tv.fill").font(.title2).foregroundStyle(Color.saTextSecondary.opacity(0.3))
                }
                VStack {
                    HStack {
                        Spacer()
                        HStack(spacing: 3) {
                            Circle().fill(.red).frame(width: 5, height: 5)
                            Text("LIVE").font(.system(size: 8, weight: .black)).foregroundStyle(.white)
                        }
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(Color.black.opacity(0.55)).clipShape(Capsule()).padding(8)
                    }
                    Spacer()
                }
                if let prog = channel.currentProgram {
                    VStack {
                        Spacer()
                        VStack(spacing: 2) {
                            Text(prog.title).font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.white).lineLimit(1)
                            let p = prog.progress
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.white.opacity(0.2)).frame(height: 2)
                                    Capsule().fill(Color.red).frame(width: geo.size.width * CGFloat(p), height: 2)
                                }
                            }.frame(height: 2)
                        }
                        .padding(.horizontal, 8).padding(.bottom, 8)
                    }
                }
            }
            #if os(tvOS)
            .frame(width: 280, height: 158)
            #else
            .frame(width: 160, height: 90)
            #endif
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.07), lineWidth: 1))
            Text(channel.name)
                #if os(tvOS)
                .font(.system(size: 20, weight: .semibold))
                #else
                .font(.system(size: 11, weight: .semibold))
                #endif
                .foregroundStyle(Color.saTextPrimary).lineLimit(1)
                #if os(tvOS)
                .frame(width: 280)
                #else
                .frame(width: 160)
                #endif
        }
    }
}

// MARK: - EPG Tab

struct EPGTabView: View {
    var viewModel: HomeViewModel
    @State private var selectedChannel: Channel?
    @State private var showPlayer = false

    var body: some View {
        // tvOS: no NavigationStack — EPG is a full-screen grid that fills the tab
        #if os(tvOS)
        EPGGridView(
            channels: viewModel.channels,
            epgMap: viewModel.epgMap,
            onChannelTap: { ch in selectedChannel = ch; showPlayer = true }
        )
        .fullScreenCover(isPresented: $showPlayer) {
            if let ch = selectedChannel {
                PlayerView(streamURL: ch.streamURL, title: ch.name,
                           posterURL: ch.logoURL, isLiveTV: true,
                           channel: ch, allChannels: viewModel.channels)
            }
        }
        #else
        NavigationStack {
            EPGGridView(
                channels: viewModel.channels,
                epgMap: viewModel.epgMap,
                onChannelTap: { ch in selectedChannel = ch; showPlayer = true }
            )
            .navigationTitle("EPG")
            #if os(macOS)
            .sheet(isPresented: $showPlayer) {
                if let ch = selectedChannel {
                    PlayerView(streamURL: ch.streamURL, title: ch.name,
                               posterURL: ch.logoURL, isLiveTV: true,
                               channel: ch, allChannels: viewModel.channels)
                }
            }
            #else
            .fullScreenCover(isPresented: $showPlayer) {
                if let ch = selectedChannel {
                    PlayerView(streamURL: ch.streamURL, title: ch.name,
                               posterURL: ch.logoURL, isLiveTV: true,
                               channel: ch, allChannels: viewModel.channels)
                }
            }
            #endif
        }
        #endif
    }
}
