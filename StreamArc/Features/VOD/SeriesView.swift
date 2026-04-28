import SwiftUI
import Kingfisher

struct SeriesView: View {

    var viewModel: HomeViewModel
    @State private var localVM = VODViewModel()
    @State private var selectedSeries: Series?
    @State private var showPaywall = false
    @State private var searchText = ""
    @State private var selectedCategory: String?

    @Environment(EntitlementManager.self) private var entitlements

    /// All unique category names sorted
    var categories: [String] {
        let cats = viewModel.series.compactMap { $0.groupTitle?.isEmpty == false ? $0.groupTitle : nil }
        return Array(Set(cats)).sorted()
    }

    /// Series grouped by category, filtered by selected category
    var groupedSeries: [(category: String, items: [Series])] {
        let source: [Series]
        if !searchText.isEmpty {
            source = viewModel.series.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
        } else {
            source = viewModel.series
        }

        var dict: [String: [Series]] = [:]
        var order: [String] = []
        for s in source {
            let key = s.groupTitle?.isEmpty == false ? s.groupTitle! : "Uncategorized"
            if dict[key] == nil { order.append(key) }
            dict[key, default: []].append(s)
        }

        let all = order.map { (category: $0, items: dict[$0]!) }
        if let selected = selectedCategory {
            return all.filter { $0.category == selected }
        }
        return all
    }

    var body: some View {
        NavigationStack {
            Group {
                if entitlements.isPremium {
                    seriesContent
                } else {
                    lockedPlaceholder
                }
            }
            .background(Color.saBackground.ignoresSafeArea())
#if os(iOS)
            .searchable(text: $searchText, prompt: "Search series")
#endif
        }
        .paywallSheet(isPresented: $showPaywall)
    }

    private var seriesContent: some View {
        Group {
            switch viewModel.loadState {
            case .idle, .loading:
                ScrollView { ShimmerGrid(columns: 3).padding(.top, 20) }
            case .error(let msg):
                ErrorView(message: msg)
            case .loaded:
                if viewModel.series.isEmpty {
                    EmptyContentView(
                        title: "No Series Found",
                        subtitle: "Your source didn't return any series. Series require an Xtream Codes or Stalker source.",
                        systemImage: "tv.and.mediabox"
                    )
                } else {
                    browseView
                }
            }
        }
        .sheet(item: $selectedSeries) { s in
            SeriesDetailView(series: s)
        }
    }

    // MARK: - Browse (Netflix-style rows)

    private var browseView: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 24) {
                // Category filter bar
                if !categories.isEmpty {
                    categoryBar
                }

                // Featured hero (only when not filtering)
                if selectedCategory == nil && searchText.isEmpty,
                   let featured = viewModel.series.first {
                    SeriesHeroView(series: featured) {
                        selectedSeries = featured
                    }
                    .padding(.horizontal)
                }

                // Category rows
                if groupedSeries.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 40))
                            .foregroundStyle(Color.saTextSecondary.opacity(0.5))
                        Text("No results for \"\(searchText)\"")
                            .font(.callout)
                            .foregroundStyle(Color.saTextSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                } else {
                    ForEach(groupedSeries, id: \.category) { group in
                        SeriesRowSection(
                            title: group.category,
                            items: group.items,
                            onSelect: { selectedSeries = $0 }
                        )
                    }
                }

                Spacer(minLength: 40)
            }
            .padding(.top, 8)
        }
        .background(Color.saBackground)
    }

    // MARK: - Category bar

    private var categoryBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                CategoryChip(title: "All", isSelected: selectedCategory == nil) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedCategory = nil
                    }
                }
                ForEach(categories, id: \.self) { cat in
                    CategoryChip(title: cat, isSelected: selectedCategory == cat) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedCategory = cat
                        }
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    private var lockedPlaceholder: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(Color.saAccent.opacity(0.1))
                    .frame(width: 120, height: 120)
                Image(systemName: "tv.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.saAccent)
            }
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

// MARK: - Series Hero View

private struct SeriesHeroView: View {
    let series: Series
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                if let posterURL = series.posterURL, let url = URL(string: posterURL) {
                    KFImage(url)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 200)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color.saSurface)
                        .frame(height: 200)
                }

                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.3),
                        .init(color: Color.saBackground.opacity(0.85), location: 0.7),
                        .init(color: Color.saBackground, location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: 6) {
                    Text("Featured Series")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.saAccent)
                        .textCase(.uppercase)
                        .tracking(1.2)

                    Text(series.title)
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                        .lineLimit(2)

                    Label("View Details", systemImage: "info.circle")
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                        .background(Color.saAccent)
                        .clipShape(Capsule())
                }
                .padding(20)
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Series Row Section

private struct SeriesRowSection: View {
    let title: String
    let items: [Series]
    let onSelect: (Series) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(items) { series in
                        SeriesPosterCard(series: series) {
                            onSelect(series)
                        }
                        .frame(width: 130)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

// MARK: - Series Poster Card

private struct SeriesPosterCard: View {
    let series: Series
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .bottomLeading) {
                    if let posterURL = series.posterURL, let url = URL(string: posterURL) {
                        KFImage(url)
                            .resizable()
                            .placeholder { ShimmerCard() }
                            .fade(duration: 0.25)
                            .scaledToFill()
                    } else {
                        Rectangle()
                            .fill(Color.saSurface)
                            .overlay {
                                Image(systemName: "tv")
                                    .font(.title2)
                                    .foregroundStyle(Color.saTextSecondary.opacity(0.3))
                            }
                    }

                    LinearGradient(
                        colors: [.clear, .black.opacity(0.5)],
                        startPoint: .center,
                        endPoint: .bottom
                    )
                }
                .aspectRatio(2/3, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.3), radius: 8, y: 4)

                Text(series.title)
                    .font(.caption)
                    .foregroundStyle(Color.saTextSecondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
    }
}
