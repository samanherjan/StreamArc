import SwiftUI

struct LiveTVView: View {

    var viewModel: HomeViewModel
    @State private var localVM = LiveTVViewModel()
    @State private var selectedChannel: Channel?
    @State private var showPlayer = false
    @State private var showPaywall = false

    @Environment(EntitlementManager.self) private var entitlements
    @Environment(AdsManager.self)          private var adsManager

    var filteredChannels: [Channel] {
        localVM.filteredChannels(from: viewModel.channels, isPremium: entitlements.isPremium)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.loadState {
                case .idle, .loading:
                    LoadingView(message: "Loading channels…")
                case .error(let msg):
                    ErrorView(message: msg) {
                        // Retry handled by HomeView task
                    }
                case .loaded:
                    channelList
                }
            }
            .navigationTitle("Live TV")
#if os(iOS)
            .searchable(text: $localVM.searchText, prompt: "Search channels")
            .toolbar { groupPicker }
#endif
        }
        .fullScreenCover(isPresented: $showPlayer) {
            if let ch = selectedChannel {
                PlayerView(streamURL: ch.streamURL, title: ch.name, isLiveTV: true,
                           channel: ch, allChannels: filteredChannels)
            }
        }
        .paywallSheet(isPresented: $showPaywall)
    }

    // MARK: - Channel list

    private var channelList: some View {
        VStack(spacing: 0) {
            List {
                ForEach(filteredChannels) { channel in
                    Button {
                        selectedChannel = channel
                        showPlayer = true
                    } label: {
                        ChannelRowView(channel: channel,
                                       isSelected: selectedChannel?.id == channel.id)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
#if os(tvOS)
                    .buttonStyle(.card)
#endif
                }

                // Free tier upgrade banner
                if localVM.isAtFreeCap {
                    HStack {
                        Image(systemName: "lock.fill")
                        Text("Upgrade for unlimited channels")
                            .font(.callout)
                        Spacer()
                        Button("StreamArc+") { showPaywall = true }
                            .buttonStyle(AccentButtonStyle())
                    }
                    .padding()
                    .listRowBackground(Color.saAccent.opacity(0.15))
                }
            }
            .listStyle(.plain)
            .background(Color.saBackground)
            .onAppear { localVM.checkFreeCap(channels: viewModel.channels, isPremium: entitlements.isPremium) }

            // Banner ad (free users, iOS only)
#if !os(tvOS)
            BannerAdView()
#endif
        }
    }

    @ToolbarContentBuilder
    private var groupPicker: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button("All Groups") { localVM.selectedGroup = nil }
                ForEach(localVM.groups(from: viewModel.channels), id: \.self) { group in
                    Button(group) { localVM.selectedGroup = group }
                }
            } label: {
                Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                    .tint(Color.saAccent)
            }
        }
    }
}
