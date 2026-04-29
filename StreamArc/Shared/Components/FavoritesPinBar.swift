import StreamArcCore
import SwiftUI
import Kingfisher

/// Horizontal quick-access bar of pinned channels.
/// Free users: up to 4 pins. Premium users: up to 8 pins.
struct FavoritesPinBar: View {

    /// All loaded channels — used to look up the full Channel object by id.
    let channels: [Channel]
    var onChannelTap: (Channel) -> Void = { _ in }

    @Environment(\.modelContext) private var modelContext
    @Environment(EntitlementManager.self) private var entitlements

    @State private var pinnedItems: [FavoriteItem] = []
    @State private var showPaywall = false

    private var pinnedChannels: [(item: FavoriteItem, channel: Channel)] {
        pinnedItems.compactMap { item in
            guard let ch = channels.first(where: { $0.id == item.contentId }) else { return nil }
            return (item, ch)
        }
    }

    private var pinCap: Int {
        entitlements.isPremium ? FavoritesManager.premiumPinCap : FavoritesManager.freePinCap
    }

    var body: some View {
        if !pinnedItems.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Pinned")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.saTextSecondary)
                    Spacer()
                    Text("\(pinnedItems.count)/\(pinCap)")
                        .font(.caption2)
                        .foregroundStyle(Color.saTextSecondary.opacity(0.6))
                }
                .padding(.horizontal)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(pinnedChannels, id: \.item.contentId) { pair in
                            PinTile(channel: pair.channel) {
                                onChannelTap(pair.channel)
                            } onUnpin: {
                                let mgr = FavoritesManager(modelContext: modelContext)
                                try? mgr.unpinChannel(contentId: pair.channel.id)
                                reload()
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 4)
                }
            }
            .onAppear { reload() }
        }
    }

    func reload() {
        let mgr = FavoritesManager(modelContext: modelContext)
        pinnedItems = (try? mgr.pinnedItems()) ?? []
    }
}

// MARK: - Pin Tile

private struct PinTile: View {
    let channel: Channel
    var onTap: () -> Void
    var onUnpin: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(Color.saCard)
                        .frame(width: 58, height: 58)

                    if let logoURL = channel.logoURL, let url = URL(string: logoURL) {
                        KFImage(url)
                            .resizable()
                            .placeholder {
                                channelInitials
                            }
                            .fade(duration: 0.2)
                            .scaledToFit()
                            .frame(width: 36, height: 36)
                            .clipShape(Circle())
                    } else {
                        channelInitials
                    }

                    // Live badge
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                        .overlay(Circle().stroke(Color.saBackground, lineWidth: 1.5))
                        .offset(x: 22, y: -22)
                }

                Text(channel.name)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.saTextPrimary)
                    .lineLimit(1)
                    .frame(width: 64)
                    .multilineTextAlignment(.center)

                if let prog = channel.currentProgram {
                    Text(prog.title)
                        .font(.system(size: 9))
                        .foregroundStyle(Color.saTextSecondary)
                        .lineLimit(1)
                        .frame(width: 64)
                }
            }
        }
        .cardFocusable()
        .contextMenu {
            Button(role: .destructive) {
                onUnpin()
            } label: {
                Label("Unpin", systemImage: "pin.slash")
            }
        }
    }

    private var channelInitials: some View {
        Text(String(channel.name.prefix(2)).uppercased())
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(Color.white)
            .frame(width: 36, height: 36)
            .background(initialsColor)
            .clipShape(Circle())
    }

    /// Deterministic color from channel name hash.
    private var initialsColor: Color {
        let colors: [Color] = [.blue, .purple, .pink, .orange, .green, .teal, .indigo, .cyan]
        let idx = abs(channel.name.hashValue) % colors.count
        return colors[idx].opacity(0.8)
    }
}
