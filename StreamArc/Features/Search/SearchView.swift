import StreamArcCore
import SwiftUI
import SwiftData

struct SearchView: View {
    var viewModel: HomeViewModel
    @State private var searchVM = SearchViewModel()
    @State private var selectedResult: SearchViewModel.SearchResult?
    @State private var showPlayer = false
    @State private var selectedVOD: VODItem?
    @State private var selectedSeries: Series?

    @Query(filter: #Predicate<Profile> { $0.isActive == true })
    private var activeProfiles: [Profile]
    private var activeProfile: Profile? { activeProfiles.first }

    var body: some View {
        NavigationStack {
            Group {
                if searchVM.query.isEmpty {
                    EmptyContentView(
                        title: "Search everything",
                        subtitle: "Search across Live TV, Movies, and Series",
                        systemImage: "magnifyingglass"
                    )
                } else {
                    let results = searchVM.results(
                        channels: viewModel.channels,
                        vodItems: viewModel.vodItems,
                        series: viewModel.series
                    )
                    if results.isEmpty {
                        EmptyContentView(title: "No results for \"\(searchVM.query)\"", subtitle: "")
                    } else {
                        #if os(tvOS)
                        // tvOS: large poster grid — minimum 200 pt wide, 3 columns
                        ScrollView {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 24)], spacing: 28) {
                                ForEach(results) { result in
                                    Button { handleTap(result) } label: {
                                        VStack(alignment: .leading, spacing: 8) {
                                            PosterCardView(title: result.title, imageURL: result.imageURL)
                                                .frame(width: 200, height: 300)
                                            Label(result.typeLabel, systemImage: result.systemImage)
                                                .font(.caption.bold())
                                                .foregroundStyle(Color.saAccent)
                                        }
                                    }
                                    .cardFocusable()
                                }
                            }
                            .padding(48)
                        }
                        .background(Color.saBackground)
                        .focusSection()
                        #else
                        List(results) { result in
                            Button { handleTap(result) } label: {
                                HStack(spacing: 12) {
                                    PosterCardView(title: "", imageURL: result.imageURL)
                                        .frame(width: 50, height: 70)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(result.title)
                                            .font(.body.bold())
                                            .foregroundStyle(Color.saTextPrimary)
                                        Label(result.typeLabel, systemImage: result.systemImage)
                                            .font(.caption)
                                            .foregroundStyle(Color.saAccent)
                                    }
                                }
                            }
                            .cardFocusable()
                            .listRowBackground(Color.clear)
                        }
                        .listStyle(.plain)
                        .background(Color.saBackground)
                        #endif
                    }
                }
            }
            .navigationTitle("Search")
            .searchable(text: $searchVM.query, prompt: "Channels, movies, series…")
        }
#if os(macOS)
        .sheet(isPresented: $showPlayer) {
            if case .channel(let ch) = selectedResult {
                PlayerView(streamURL: ch.streamURL, title: ch.name, isLiveTV: true,
                           channel: ch, allChannels: viewModel.channels, profile: activeProfile)
            }
        }
#else
        .fullScreenCover(isPresented: $showPlayer) {
            if case .channel(let ch) = selectedResult {
                PlayerView(streamURL: ch.streamURL, title: ch.name, isLiveTV: true,
                           channel: ch, allChannels: viewModel.channels, profile: activeProfile)
            }
        }
#endif
#if os(tvOS)
        .fullScreenCover(item: $selectedVOD) { vod in
            MovieDetailView(item: vod)
        }
        .fullScreenCover(item: $selectedSeries) { series in
            SeriesDetailView(series: series)
        }
#else
        .sheet(item: $selectedVOD) { vod in
            MovieDetailView(item: vod)
        }
        .sheet(item: $selectedSeries) { series in
            SeriesDetailView(series: series)
        }
#endif
    }

    private func handleTap(_ result: SearchViewModel.SearchResult) {
        selectedResult = result
        switch result {
        case .channel:    showPlayer = true
        case .vod(let v): selectedVOD = v
        case .series(let s): selectedSeries = s
        }
    }
}
