import StreamArcCore
import SwiftUI
import Kingfisher

// MARK: - Category Browser Card

/// A card representing a single content category in the "Your Library" grid.
struct CategoryBrowserCard: View {
    let title: String
    let count: Int
    let samplePosters: [String?] // up to 4 poster URLs for the mini collage

    @Environment(\.isFocused) private var isFocused

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {

            // Mini poster collage (2×2 grid) — fixed aspect ratio, no GeometryReader
            Color.saCard
                .aspectRatio(16 / 9, contentMode: .fit)
                .overlay(
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 1), GridItem(.flexible(), spacing: 1)], spacing: 1) {
                        ForEach(0..<4, id: \.self) { i in
                            if i < samplePosters.count, let urlStr = samplePosters[i], let url = URL(string: urlStr) {
                                KFImage(url)
                                    .resizable()
                                    .scaledToFill()
                                    .clipped()
                            } else {
                                Color.saSurface
                                    .overlay(Image(systemName: "photo").font(.caption2)
                                        .foregroundStyle(Color.saTextSecondary.opacity(0.3)))
                            }
                        }
                    }
                )
                .overlay(LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .top, endPoint: .bottom))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            // Title + count
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.saTextPrimary)
                    .lineLimit(1)
                Text("\(count) \(count == 1 ? "title" : "titles")")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.saTextSecondary)
            }
        }
        .padding(.bottom, 4)
    }

}

// MARK: - Movie Category Detail View

struct MovieCategoryDetailView: View {
    let category: String
    let movies: [VODItem]

    @State private var selectedItem: VODItem?
    @State private var searchText = ""

    private var filteredMovies: [VODItem] {
        searchText.isEmpty ? movies : movies.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    private let columns: [GridItem] = {
        #if os(tvOS)
        return Array(repeating: GridItem(.flexible(), spacing: 20), count: 5)
        #elseif os(macOS)
        return Array(repeating: GridItem(.flexible(), spacing: 16), count: 4)
        #else
        return Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)
        #endif
    }()

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(filteredMovies) { movie in
                    Button { selectedItem = movie } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            PosterCardView(title: movie.title, imageURL: movie.posterURL)
                                .aspectRatio(2/3, contentMode: .fit)
                            Text(movie.title)
                                .font(.caption)
                                .foregroundStyle(Color.saTextSecondary)
                                .lineLimit(1)
                        }
                    }
                    .cardFocusable()
                }
            }
            .padding()
        }
        .background(Color.saBackground.ignoresSafeArea())
        .navigationTitle(category)
        #if !os(tvOS)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        #if !os(macOS)
        .searchable(text: $searchText, prompt: "Search \(category)")
        #endif
        #endif
        #if os(macOS)
        .sheet(item: $selectedItem) { MovieDetailView(item: $0) }
        #else
        .fullScreenCover(item: $selectedItem) { MovieDetailView(item: $0) }
        #endif
    }
}

// MARK: - Series Category Detail View

struct SeriesCategoryDetailView: View {
    let category: String
    let series: [Series]

    @State private var selectedSeries: Series?
    @State private var searchText = ""

    private var filteredSeries: [Series] {
        searchText.isEmpty ? series : series.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    private let columns: [GridItem] = {
        #if os(tvOS)
        return Array(repeating: GridItem(.flexible(), spacing: 20), count: 5)
        #elseif os(macOS)
        return Array(repeating: GridItem(.flexible(), spacing: 16), count: 4)
        #else
        return Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)
        #endif
    }()

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(filteredSeries) { item in
                    Button { selectedSeries = item } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            PosterCardView(title: item.title, imageURL: item.posterURL)
                                .aspectRatio(2/3, contentMode: .fit)
                            Text(item.title)
                                .font(.caption)
                                .foregroundStyle(Color.saTextSecondary)
                                .lineLimit(1)
                        }
                    }
                    .cardFocusable()
                }
            }
            .padding()
        }
        .background(Color.saBackground.ignoresSafeArea())
        .navigationTitle(category)
        #if !os(tvOS)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        #if !os(macOS)
        .searchable(text: $searchText, prompt: "Search \(category)")
        #endif
        #endif
        #if os(macOS)
        .sheet(item: $selectedSeries) { SeriesDetailView(series: $0) }
        #elseif os(tvOS)
        .fullScreenCover(item: $selectedSeries) { SeriesDetailView(series: $0) }
        #else
        .sheet(item: $selectedSeries) { SeriesDetailView(series: $0) }
        #endif
    }
}

// MARK: - All Category Card (generic)

struct AllCategoryCard: View {
    let title: String
    let icon: String
    let count: Int

    @Environment(\.isFocused) private var isFocused

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(LinearGradient(
                        colors: [Color.saAccent.opacity(0.9), Color.saAccent.opacity(0.5)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
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
            Text("\(count) \(count == 1 ? "title" : "titles")")
                .font(.system(size: 12))
                .foregroundStyle(Color.saTextSecondary)
        }
        .padding(.bottom, 4)
    }
}
