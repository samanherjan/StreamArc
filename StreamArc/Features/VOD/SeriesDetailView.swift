import SwiftUI

struct SeriesDetailView: View {
    let series: Series
    @Environment(\.dismiss) private var dismiss
    @State private var selectedSeason: Season?
    @State private var selectedEpisode: Episode?
    @State private var showPlayer = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    HStack(alignment: .top, spacing: 16) {
                        PosterCardView(title: series.title, imageURL: series.posterURL)
                            .frame(width: 100, height: 150)
                        VStack(alignment: .leading, spacing: 8) {
                            Text(series.title)
                                .font(.title2.bold())
                                .foregroundStyle(Color.saTextPrimary)
                            if let desc = series.description {
                                Text(desc).font(.caption).foregroundStyle(Color.saTextSecondary)
                            }
                            // Trailer
                            if let vodItem = series.asVODItem {
                                TrailerButton(item: vodItem)
                            }
                        }
                    }
                    .padding(.horizontal)

                    // Season picker
                    if !series.seasons.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(series.seasons) { season in
                                    Button("Season \(season.seasonNumber)") {
                                        selectedSeason = season
                                    }
                                    .buttonStyle(selectedSeason?.id == season.id
                                        ? AccentButtonStyle()
                                        : SecondaryButtonStyle())
                                }
                            }
                            .padding(.horizontal)
                        }
                        .onAppear { selectedSeason = series.seasons.first }
                    }

                    // Episode list
                    if let season = selectedSeason ?? series.seasons.first {
                        ForEach(season.episodes) { episode in
                            Button {
                                selectedEpisode = episode
                                showPlayer = true
                            } label: {
                                HStack {
                                    Text("\(episode.episodeNumber)")
                                        .font(.headline)
                                        .frame(width: 36)
                                        .foregroundStyle(Color.saAccent)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(episode.title).font(.body).foregroundStyle(Color.saTextPrimary)
                                        if let desc = episode.description {
                                            Text(desc).font(.caption).foregroundStyle(Color.saTextSecondary).lineLimit(1)
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: "play.circle")
                                        .foregroundStyle(Color.saAccent)
                                }
                                .padding()
                                .background(Color.saSurface)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .padding(.horizontal)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.vertical)
            }
            .background(Color.saBackground)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .fullScreenCover(isPresented: $showPlayer) {
            if let ep = selectedEpisode {
                PlayerView(streamURL: ep.streamURL, title: ep.title)
            }
        }
    }
}

// Helper to create a VODItem stub from a Series for the TrailerButton
extension Series {
    var asVODItem: VODItem? {
        VODItem(id: id, title: title, posterURL: posterURL, streamURL: "", tmdbId: tmdbId, type: .series)
    }
}
