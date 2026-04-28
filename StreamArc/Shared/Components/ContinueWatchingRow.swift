import StreamArcCore
import SwiftUI
import SwiftData
import Kingfisher

/// Horizontal row showing recently watched items with progress bars.
/// Only shows for premium users.
struct ContinueWatchingRow: View {

    @Environment(EntitlementManager.self) private var entitlements
    @Environment(\.modelContext) private var modelContext
    @State private var items: [WatchHistoryEntry] = []

    var onTap: (WatchHistoryEntry) -> Void = { _ in }

    var body: some View {
        if entitlements.isPremium && !items.isEmpty {
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
                        ForEach(items) { entry in
                            Button { onTap(entry) } label: {
                                ContinueWatchingCard(entry: entry)
                            }
                            .cardFocusable()
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .onAppear { loadHistory() }
        }
    }

    private func loadHistory() {
        let mgr = WatchHistoryManager(modelContext: modelContext)
        items = (try? mgr.recentItems(limit: 15)) ?? []
        // Only show items with meaningful progress (> 2% and < 95%)
        items = items.filter { $0.progress > 0.02 && $0.progress < 0.95 }
    }
}

private struct ContinueWatchingCard: View {
    let entry: WatchHistoryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottomLeading) {
                if let url = entry.imageURL, let imgURL = URL(string: url) {
                    KFImage(imgURL)
                        .resizable()
                        .scaledToFill()
                } else {
                    Rectangle()
                        .fill(Color.saSurface)
                        .overlay {
                            Image(systemName: "play.rectangle")
                                .font(.title2)
                                .foregroundStyle(Color.saTextSecondary.opacity(0.3))
                        }
                }

                // Progress bar
                GeometryReader { geo in
                    VStack {
                        Spacer()
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(Color.white.opacity(0.3))
                                .frame(height: 3)
                            Rectangle()
                                .fill(Color.saAccent)
                                .frame(width: geo.size.width * entry.progress, height: 3)
                        }
                    }
                }
            }
            .frame(width: 160, height: 90)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            Text(entry.title)
                .font(.caption)
                .foregroundStyle(Color.saTextSecondary)
                .lineLimit(1)
                .frame(width: 160, alignment: .leading)
        }
    }
}
