import SwiftUI

struct SeriesView: View {

    var viewModel: HomeViewModel
    @State private var localVM = VODViewModel()
    @State private var selectedSeries: Series?
    @State private var showPaywall = false

    @Environment(EntitlementManager.self) private var entitlements

    private let columns = [GridItem(.adaptive(minimum: 120, maximum: 180), spacing: 12)]

    var body: some View {
        NavigationStack {
            Group {
                if entitlements.isPremium {
                    seriesContent
                } else {
                    lockedPlaceholder
                }
            }
            .navigationTitle("Series")
        }
        .paywallSheet(isPresented: $showPaywall)
    }

    private var seriesContent: some View {
        Group {
            switch viewModel.loadState {
            case .idle, .loading:
                ScrollView { ShimmerGrid(columns: 3) }
            case .error(let msg):
                ErrorView(message: msg)
            case .loaded:
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(viewModel.series) { series in
                            Button {
                                selectedSeries = series
                            } label: {
                                PosterCardView(title: series.title, imageURL: series.posterURL)
                                    .aspectRatio(2/3, contentMode: .fit)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
                .background(Color.saBackground)
            }
        }
        .sheet(item: $selectedSeries) { s in
            SeriesDetailView(series: s)
        }
    }

    private var lockedPlaceholder: some View {
        VStack(spacing: 24) {
            Image(systemName: "lock.tv.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color.saAccent)
            Text("TV Series")
                .font(.title.bold())
                .foregroundStyle(Color.saTextPrimary)
            Text("Unlock the full series section with StreamArc+")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.saTextSecondary)
                .padding(.horizontal, 40)
            Button("Upgrade to StreamArc+") { showPaywall = true }
                .buttonStyle(AccentButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .streamArcBackground()
    }
}
