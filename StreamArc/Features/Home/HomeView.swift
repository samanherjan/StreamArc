import SwiftUI
import SwiftData

// ContentRootView: routes between onboarding and the main UI.
struct ContentRootView: View {
    @Query private var profiles: [Profile]
    @Environment(AppEnvironment.self) private var appEnv

    var body: some View {
        if profiles.isEmpty {
            OnboardingView()
        } else {
            HomeView()
        }
    }
}

// MARK: - HomeView

struct HomeView: View {

    @Query(filter: #Predicate<Profile> { $0.isActive == true })
    private var activeProfiles: [Profile]

    @Query private var allProfiles: [Profile]

    @State private var viewModel = HomeViewModel()
    @State private var selectedTab: Tab = .liveTV
    @State private var showAddProfile = false

    @Environment(AdsManager.self)          private var adsManager
    @Environment(InterstitialAdManager.self) private var interstitialManager

    enum Tab: Int, CaseIterable {
        case liveTV, movies, series, search, settings
        var title: String {
            switch self { case .liveTV: "Live TV"; case .movies: "Movies"
            case .series: "Series"; case .search: "Search"; case .settings: "Settings" }
        }
        var systemImage: String {
            switch self { case .liveTV: "tv"; case .movies: "film"
            case .series: "tv.and.mediabox"; case .search: "magnifyingglass"; case .settings: "gearshape" }
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

    // MARK: - iOS layout

    #if os(iOS)
    private var iOSLayout: some View {
        iOSTabView
            .tint(Color.saAccent)
            .streamArcBackground()
            .onChange(of: selectedTab) { _, _ in
                interstitialManager.recordTabSwitch()
            }
            .task(id: activeProfile?.id) {
                if let profile = activeProfile {
                    await viewModel.load(profile: profile)
                } else {
                    viewModel.noActiveProfile()
                }
            }
    }

    @ViewBuilder
    private var iOSTabView: some View {
        if #available(iOS 18, *) {
            TabView(selection: $selectedTab) {
                ForEach(Tab.allCases, id: \.self) { tab in
                    tabContent(tab)
                        .tabItem { Label(tab.title, systemImage: tab.systemImage) }
                        .tag(tab)
                }
            }
            .tabViewStyle(.tabBarOnly)
        } else {
            TabView(selection: $selectedTab) {
                ForEach(Tab.allCases, id: \.self) { tab in
                    tabContent(tab)
                        .tabItem { Label(tab.title, systemImage: tab.systemImage) }
                        .tag(tab)
                }
            }
        }
    }
    #endif

    // MARK: - tvOS layout

    #if os(tvOS)
    private var tvLayout: some View {
        TabView(selection: $selectedTab) {
            ForEach(Tab.allCases, id: \.self) { tab in
                tabContent(tab)
                    .tabItem { Label(tab.title, systemImage: tab.systemImage) }
                    .tag(tab)
            }
        }
        .task(id: activeProfile?.id) {
            if let profile = activeProfile {
                await viewModel.load(profile: profile)
            } else {
                viewModel.noActiveProfile()
            }
        }
    }
    #endif

    // MARK: - macOS layout

    #if os(macOS)
    private var macLayout: some View {
        NavigationSplitView {
            List(Tab.allCases, id: \.self, selection: $selectedTab) { tab in
                Label(tab.title, systemImage: tab.systemImage)
                    .tag(tab)
            }
            .listStyle(.sidebar)
            .navigationTitle("StreamArc")
        } detail: {
            tabContent(selectedTab)
        }
        .task(id: activeProfile?.id) {
            if let profile = activeProfile {
                await viewModel.load(profile: profile)
            } else {
                viewModel.noActiveProfile()
            }
        }
    }
    #endif

    // MARK: - Tab content

    @ViewBuilder
    private func tabContent(_ tab: Tab) -> some View {
        switch tab {
        case .liveTV:
            LiveTVView(viewModel: viewModel)
        case .movies:
            MoviesView(viewModel: viewModel)
        case .series:
            SeriesView(viewModel: viewModel)
        case .search:
            SearchView(viewModel: viewModel)
        case .settings:
            SettingsView()
        }
    }
}
