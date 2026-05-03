import StreamArcCore
import SwiftUI
import SwiftData
import Kingfisher

// MARK: - Continue Watching Row

/// Horizontal shelf showing:
///   • In-progress movies/episodes (2% – 95% watched)
///   • "Up Next" — the episode that follows a recently-finished one
///
/// Pass `seriesLibrary` so the view can resolve next-episode pointers.
struct ContinueWatchingRow: View {

    /// Full series library — used to resolve next episodes.
    var seriesLibrary: [Series] = []

    @Environment(EntitlementManager.self) private var entitlements
    @Environment(\.modelContext) private var modelContext

    /// Called when the user taps a card.
    /// `entry` is the raw WatchHistoryEntry; `nextEpisode` is non-nil when the
    /// card represents the *next* episode (i.e., the previous one was finished).
    var onTap: (_ entry: WatchHistoryEntry, _ nextEpisode: Episode?) -> Void = { _, _ in }

    @State private var displayItems: [ContinueItem] = []

    var body: some View {
        if entitlements.isPremium && !displayItems.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Continue Watching")
                        .font(.title3.bold())
                        .foregroundStyle(Color.saTextPrimary)
                    Spacer()
                }
                .padding(.horizontal)

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(displayItems) { item in
                            Button { onTap(item.entry, item.nextEpisode) } label: {
                                ContinueWatchingCard(item: item)
                            }
                            .cardFocusable()
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .onAppear { buildDisplayItems() }
            .onChange(of: seriesLibrary.count) { _, _ in buildDisplayItems() }
        }
    }

    // MARK: - Build display items

    private func buildDisplayItems() {
        let mgr  = WatchHistoryManager(modelContext: modelContext)
        let raw  = (try? mgr.recentItems(limit: 30)) ?? []

        // Only VOD and episodes (not live channels)
        let relevant = raw.filter { $0.contentType == "vod" || $0.contentType == "episode" }

        var result: [ContinueItem] = []
        var seenSeriesIds = Set<String>()   // deduplicate: one card per series

        for entry in relevant {
            if entry.contentType == "vod" {
                // Movie: show only if meaningfully in progress
                if entry.progress > 0.02 && entry.progress < 0.95 {
                    result.append(ContinueItem(entry: entry))
                }
            } else {
                // Episode: find which series it belongs to
                guard let (series, season, episode) = findEpisode(id: entry.contentId) else {
                    // Unknown episode — still show if in-progress
                    if entry.progress > 0.02 && entry.progress < 0.95 {
                        result.append(ContinueItem(entry: entry))
                    }
                    continue
                }

                // Skip if we already have a card for this series
                if seenSeriesIds.contains(series.id) { continue }
                seenSeriesIds.insert(series.id)

                if entry.progress >= 0.95 {
                    // Finished — find the next episode
                    if let (nextSeason, nextEp) = nextEpisode(after: episode, in: season, series: series) {
                        result.append(ContinueItem(
                            entry: entry,
                            nextEpisode: nextEp,
                            overrideTitle: "S\(nextSeason.seasonNumber)·E\(nextEp.episodeNumber) – \(nextEp.title)",
                            overrideImage: nextEp.posterURL ?? series.posterURL,
                            badgeLabel: "Up Next",
                            progress: 0   // next episode hasn't started
                        ))
                    }
                    // else: series finished, don't show
                } else if entry.progress > 0.02 {
                    // In-progress episode
                    result.append(ContinueItem(
                        entry: entry,
                        overrideTitle: "S\(season.seasonNumber)·E\(episode.episodeNumber) – \(episode.title)",
                        overrideImage: episode.posterURL ?? series.posterURL,
                        badgeLabel: nil,
                        progress: entry.progress
                    ))
                }
            }
        }

        // Cap at 15 cards
        displayItems = Array(result.prefix(15))
    }

    // MARK: - Helpers

    /// Finds an episode by ID across all series in the library.
    private func findEpisode(id: String) -> (series: Series, season: Season, episode: Episode)? {
        for series in seriesLibrary {
            for season in series.seasons {
                if let ep = season.episodes.first(where: { $0.id == id }) {
                    return (series, season, ep)
                }
            }
        }
        return nil
    }

    /// Returns the (season, episode) that follows `episode` in the series.
    /// Advances to the next season when needed.
    private func nextEpisode(after episode: Episode, in season: Season, series: Series) -> (Season, Episode)? {
        let sortedSeasons = series.seasons.sorted { $0.seasonNumber < $1.seasonNumber }

        // Find next episode in the same season
        let eps = season.episodes.sorted { $0.episodeNumber < $1.episodeNumber }
        if let idx = eps.firstIndex(where: { $0.id == episode.id }), idx + 1 < eps.count {
            return (season, eps[idx + 1])
        }

        // Advance to next season
        if let sIdx = sortedSeasons.firstIndex(where: { $0.seasonNumber == season.seasonNumber }),
           sIdx + 1 < sortedSeasons.count {
            let nextSeason = sortedSeasons[sIdx + 1]
            if let firstEp = nextSeason.episodes.sorted(by: { $0.episodeNumber < $1.episodeNumber }).first {
                return (nextSeason, firstEp)
            }
        }

        return nil   // series is complete
    }
}

// MARK: - Display model

private struct ContinueItem: Identifiable {
    let id = UUID()
    let entry: WatchHistoryEntry
    var nextEpisode: Episode? = nil
    var overrideTitle: String? = nil
    var overrideImage: String? = nil
    var badgeLabel: String? = nil
    var progress: Double? = nil   // nil → use entry.progress

    var displayTitle: String { overrideTitle ?? entry.title }
    var displayImage: String? { overrideImage ?? entry.imageURL }
    var displayProgress: Double { progress ?? entry.progress }
}

// MARK: - Card

private struct ContinueWatchingCard: View {
    let item: ContinueItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottom) {
                // Thumbnail
                Group {
                    if let url = item.displayImage.flatMap(URL.init) {
                        KFImage(url)
                            .resizable()
                            .placeholder {
                                Rectangle().fill(Color.saSurface)
                                    .overlay { Image(systemName: "play.rectangle")
                                        .font(.title2).foregroundStyle(Color.saTextSecondary.opacity(0.3)) }
                            }
                            .fade(duration: 0.2)
                            .scaledToFill()
                    } else {
                        Rectangle().fill(Color.saSurface)
                            .overlay { Image(systemName: "play.rectangle")
                                .font(.title2).foregroundStyle(Color.saTextSecondary.opacity(0.3)) }
                    }
                }

                // Gradient + progress bar
                VStack(spacing: 0) {
                    Spacer()
                    LinearGradient(colors: [.clear, .black.opacity(0.6)],
                                   startPoint: .center, endPoint: .bottom)
                        .frame(height: 40)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(Color.white.opacity(0.25)).frame(height: 3)
                            Rectangle().fill(Color.saAccent)
                                .frame(width: geo.size.width * item.displayProgress, height: 3)
                        }
                    }
                    .frame(height: 3)
                }

                // "Up Next" badge
                if let badge = item.badgeLabel {
                    VStack {
                        HStack {
                            Text(badge)
                                .font(.system(size: 9, weight: .black))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6).padding(.vertical, 3)
                                .background(Color.saAccent)
                                .clipShape(Capsule())
                                .padding(8)
                            Spacer()
                        }
                        Spacer()
                    }
                }

                // Play icon overlay
                Image(systemName: item.badgeLabel != nil ? "play.fill" : "play.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(6)
                    .background(.black.opacity(0.45))
                    .clipShape(Circle())
            }
            .frame(width: cardWidth, height: cardHeight)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.35), radius: 6, y: 3)

            // Title
            Text(item.displayTitle)
                .font(.caption)
                .foregroundStyle(Color.saTextSecondary)
                .lineLimit(2)
                .frame(width: cardWidth, alignment: .leading)
        }
    }

    private var cardWidth: CGFloat {
        #if os(tvOS)
        return 240
        #else
        return 160
        #endif
    }
    private var cardHeight: CGFloat {
        #if os(tvOS)
        return 135
        #else
        return 90
        #endif
    }
}
