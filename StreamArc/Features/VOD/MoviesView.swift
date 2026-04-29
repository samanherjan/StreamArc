import StreamArcCore
import SwiftUI
import Kingfisher

struct MoviesView: View {

    var viewModel: HomeViewModel
    @State private var localVM = VODViewModel()
    @State private var selectedItem: VODItem?
    @State private var showPaywall = false

    @Environment(EntitlementManager.self) private var entitlements
    @Environment(AdsManager.self)          private var adsManager

    var movies: [VODItem] {
        localVM.filteredMovies(from: viewModel.vodItems, isPremium: entitlements.isPremium)
    }

    /// Movies grouped by category, preserving group order
    var groupedMovies: [(category: String, items: [VODItem])] {
        let allMovies = localVM.filteredMovies(from: viewModel.vodItems, isPremium: entitlements.isPremium, ignoreGroupFilter: true)
        var dict: [String: [VODItem]] = [:]
        var order: [String] = []
        for movie in allMovies {
            let key = movie.groupTitle.isEmpty ? "Uncategorized" : movie.groupTitle
            if dict[key] == nil { order.append(key) }
            dict[key, default: []].append(movie)
        }
        return order.map { (category: $0, items: dict[$0]!) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Group {
                    switch viewModel.loadState {
                    case .idle, .loading:
                        ScrollView {
                            ShimmerGrid(columns: 3)
                                .padding(.top, 20)
                        }
                    case .error(let msg):
                        ErrorView(message: msg)
                    case .loaded:
                        if viewModel.vodItems.isEmpty {
                            EmptyContentView(
                                title: "No Movies Found",
                                subtitle: "Your source didn't return any movies. Check your source settings and try again.",
                                systemImage: "film.fill"
                            )
                        } else {
                            movieContent
                        }
                    }
                }

#if !os(tvOS)
                BannerAdView()
#endif
            }
            .background(Color.saBackground.ignoresSafeArea())
            .searchable(text: $localVM.searchText, prompt: "Search movies")
#if os(tvOS)
            .fullScreenCover(item: $selectedItem) { item in
                MovieDetailView(item: item)
            }
#else
            .sheet(item: $selectedItem) { item in
                MovieDetailView(item: item)
            }
#endif
        }
    }

    // MARK: - Movie content

    private var movieContent: some View {
        Group {
            if !localVM.searchText.isEmpty {
                // Search results: flat grid
                searchResults
            } else {
                // Browse: Netflix-style rows
                browseView
            }
        }
    }

    // MARK: - Browse (Netflix-style)

    private var browseView: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 28) {
                // Continue Watching
                ContinueWatchingRow()

                // Featured hero
                if let featured = groupedMovies.first?.items.first {
                    FeaturedHeroView(item: featured) {
                        selectedItem = featured
                    }
                    .padding(.horizontal)
                }

                // Category rows
                ForEach(groupedMovies, id: \.category) { group in
                    MovieRowSection(
                        title: group.category,
                        items: group.items,
                        onSelect: { selectedItem = $0 }
                    )
                }

                // Upgrade prompt
                if localVM.isAtFreeCap(items: viewModel.vodItems, isPremium: entitlements.isPremium) {
                    upgradeRow
                }

                Spacer(minLength: 40)
            }
            .padding(.top, 8)
        }
        .background(Color.saBackground)
    }

    // MARK: - Search results

    private var searchResults: some View {
        let cols = [GridItem(.adaptive(minimum: 110, maximum: 160), spacing: 14)]
        return Group {
            if movies.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 40))
                        .foregroundStyle(Color.saTextSecondary.opacity(0.5))
                    Text("No results for \"\(localVM.searchText)\"")
                        .font(.callout)
                        .foregroundStyle(Color.saTextSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: cols, spacing: 14) {
                        ForEach(movies) { item in
                            MoviePosterCard(item: item) {
                                selectedItem = item
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .background(Color.saBackground)
            }
        }
    }

    // MARK: - Upgrade row

    private var upgradeRow: some View {
        Button { showPaywall = true } label: {
            HStack(spacing: 16) {
                Image(systemName: "sparkles")
                    .font(.title2)
                    .foregroundStyle(Color.saAccent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Unlock All Movies")
                        .font(.subheadline.bold())
                        .foregroundStyle(Color.saTextPrimary)
                    Text("Upgrade to StreamArc+ for unlimited access")
                        .font(.caption)
                        .foregroundStyle(Color.saTextSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(Color.saAccent)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.saAccent.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.saAccent.opacity(0.2), lineWidth: 1)
                    )
            )
            .padding(.horizontal)
        }
        .cardFocusable()
        .paywallSheet(isPresented: $showPaywall)
    }
}

// MARK: - Featured Hero View

private struct FeaturedHeroView: View {
    let item: VODItem
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                // Background poster
                if let posterURL = item.posterURL, let url = URL(string: posterURL) {
                    KFImage(url)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 220)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color.saSurface)
                        .frame(height: 220)
                }

                // Gradient overlay
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.3),
                        .init(color: Color.saBackground.opacity(0.85), location: 0.7),
                        .init(color: Color.saBackground, location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                // Content
                VStack(alignment: .leading, spacing: 8) {
                    Text("Featured")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.saAccent)
                        .textCase(.uppercase)
                        .tracking(1.2)

                    Text(item.title)
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                        .lineLimit(2)

                    HStack(spacing: 12) {
                        Label("Play", systemImage: "play.fill")
                            .font(.subheadline.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Color.saAccent)
                            .clipShape(Capsule())

                        if let year = item.year {
                            Text(String(year))
                                .font(.caption)
                                .foregroundStyle(Color.saTextSecondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(.ultraThinMaterial)
                                .clipShape(Capsule())
                        }
                    }
                }
                .padding(20)
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .cardFocusable()
    }
}

// MARK: - Movie Row Section (horizontal scroll)

private struct MovieRowSection: View {
    let title: String
    let items: [VODItem]
    let onSelect: (VODItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            HStack {
                Text(title)
                    .font(.title3.bold())
                    .foregroundStyle(Color.saTextPrimary)
                Spacer()
                Text("\(items.count)")
                    .font(.caption)
                    .foregroundStyle(Color.saTextSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.saCard)
                    .clipShape(Capsule())
            }
            .padding(.horizontal)

            // Horizontal poster scroll
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(items) { item in
                        MoviePosterCard(item: item) {
                            onSelect(item)
                        }
                        .frame(width: 130)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

// MARK: - Movie Poster Card (modern)

private struct MoviePosterCard: View {
    let item: VODItem
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                // Poster
                ZStack(alignment: .bottomLeading) {
                    if let posterURL = item.posterURL, let url = URL(string: posterURL) {
                        KFImage(url)
                            .resizable()
                            .placeholder { ShimmerCard() }
                            .fade(duration: 0.25)
                            .scaledToFill()
                    } else {
                        Rectangle()
                            .fill(Color.saSurface)
                            .overlay {
                                Image(systemName: "film")
                                    .font(.title2)
                                    .foregroundStyle(Color.saTextSecondary.opacity(0.3))
                            }
                    }

                    // Subtle gradient at bottom
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.5)],
                        startPoint: .center,
                        endPoint: .bottom
                    )

                    // Year badge
                    if let year = item.year {
                        Text(String(year))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .padding(8)
                    }
                }
                .aspectRatio(2/3, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
                .scaleEffect(isHovered ? 1.05 : 1.0)
                .animation(.spring(response: 0.3), value: isHovered)

                // Title
                Text(item.title)
                    .font(.caption)
                    .foregroundStyle(Color.saTextSecondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .cardFocusable()
#if os(macOS)
        .onHover { isHovered = $0 }
#endif
    }
}
