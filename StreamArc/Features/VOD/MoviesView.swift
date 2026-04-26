import SwiftUI

struct MoviesView: View {

    var viewModel: HomeViewModel
    @State private var localVM = VODViewModel()
    @State private var selectedItem: VODItem?
    @State private var showPaywall = false

    @Environment(EntitlementManager.self) private var entitlements
    @Environment(AdsManager.self)          private var adsManager

    private let columns = [GridItem(.adaptive(minimum: 120, maximum: 180), spacing: 12)]

    var movies: [VODItem] {
        localVM.filteredMovies(from: viewModel.vodItems, isPremium: entitlements.isPremium)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Group {
                    switch viewModel.loadState {
                    case .idle, .loading:
                        ScrollView { ShimmerGrid(columns: 3) }
                    case .error(let msg):
                        ErrorView(message: msg)
                    case .loaded:
                        movieGrid
                    }
                }

#if !os(tvOS)
                BannerAdView()
#endif
            }
            .navigationTitle("Movies")
#if os(iOS)
            .searchable(text: $localVM.searchText, prompt: "Search movies")
#endif
            .sheet(item: $selectedItem) { item in
                MovieDetailView(item: item)
            }
        }
    }

    private var movieGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(movies) { item in
                    Button {
                        selectedItem = item
                    } label: {
                        PosterCardView(title: item.title, imageURL: item.posterURL)
                            .aspectRatio(2/3, contentMode: .fit)
                    }
                    .buttonStyle(.plain)
#if os(tvOS)
                    .buttonStyle(.card)
                    .focusable()
#endif
                }

                if localVM.isAtFreeCap(items: viewModel.vodItems, isPremium: entitlements.isPremium) {
                    upgradeCard
                }
            }
            .padding()
        }
        .background(Color.saBackground)
    }

    private var upgradeCard: some View {
        Button { showPaywall = true } label: {
            VStack(spacing: 12) {
                Image(systemName: "lock.fill")
                    .font(.largeTitle)
                    .foregroundStyle(Color.saAccent)
                Text("Upgrade for\nunlimited movies")
                    .font(.caption.bold())
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.saTextPrimary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 180)
            .background(Color.saAccent.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .paywallSheet(isPresented: $showPaywall)
    }
}
