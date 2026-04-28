import SwiftUI
import Kingfisher

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

    /// Channels grouped by category
    var groupedChannels: [(category: String, channels: [Channel])] {
        let all = localVM.allCappedChannels(from: viewModel.channels, isPremium: entitlements.isPremium)
        var dict: [String: [Channel]] = [:]
        var order: [String] = []
        for ch in all {
            let key = ch.groupTitle.isEmpty ? "General" : ch.groupTitle
            if dict[key] == nil { order.append(key) }
            dict[key, default: []].append(ch)
        }
        return order.map { (category: $0, channels: dict[$0]!) }
    }

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.loadState {
                case .idle, .loading:
                    LoadingView(message: "Loading channels…")
                case .error(let msg):
                    ErrorView(message: msg) { }
                case .loaded:
                    if viewModel.channels.isEmpty {
                        EmptyContentView(
                            title: "No Channels Found",
                            subtitle: "Your source didn't return any live channels. Check your source settings and try again.",
                            systemImage: "tv.slash"
                        )
                    } else {
                        channelContent
                    }
                }
            }
            .background(Color.saBackground.ignoresSafeArea())
#if os(iOS)
            .searchable(text: $localVM.searchText, prompt: "Search channels")
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

    // MARK: - Content

    private var channelContent: some View {
        VStack(spacing: 0) {
            if !localVM.searchText.isEmpty {
                // Search: flat list
                searchResults
            } else {
                // Browse: category sections
                browseView
            }

            if localVM.isAtFreeCap {
                upgradeBar
            }

#if !os(tvOS)
            BannerAdView()
#endif
        }
        .onAppear { localVM.checkFreeCap(channels: viewModel.channels, isPremium: entitlements.isPremium) }
    }

    // MARK: - Browse (country → category → channels)

    private var browseView: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 16) {
                // Navigation / breadcrumb bar
                navigationBar

                if localVM.selectedGroup != nil {
                    // Level 3: Channels in selected category
                    let channels = groupedChannels.first(where: { $0.category == localVM.selectedGroup })?.channels ?? []
                    channelGrid(channels: channels)
                } else if let country = localVM.selectedCountry {
                    // Level 2: Categories within selected country
                    categoryList(for: country)
                } else {
                    // Level 1: Country cards
                    countryGrid
                }

                Spacer(minLength: 20)
            }
        }
        .background(Color.saBackground)
    }

    // MARK: - Navigation bar (breadcrumb + pills)

    private var navigationBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Breadcrumb back button
            if localVM.selectedCountry != nil {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        localVM.goBack()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                            .font(.caption.bold())
                        if let group = localVM.selectedGroup {
                            let (_, clean) = LiveTVViewModel.parseCountryCode(from: group)
                            Text(clean)
                                .font(.subheadline.weight(.semibold))
                        } else if let country = localVM.selectedCountry {
                            Text(LiveTVViewModel.countryDisplayName(for: country))
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                    .foregroundStyle(Color.saAccent)
                }
                .buttonStyle(.plain)
                .padding(.horizontal)
            }

            // Country pill bar (always visible)
            countryPillBar
        }
    }

    private var countryPillBar: some View {
        let codes = localVM.countryCodes(from: viewModel.channels, isPremium: entitlements.isPremium)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                CategoryChip(title: "All", isSelected: localVM.selectedCountry == nil) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        localVM.selectedCountry = nil
                        localVM.selectedGroup = nil
                    }
                }
                ForEach(codes, id: \.self) { code in
                    CategoryChip(
                        title: "\(LiveTVViewModel.flagEmoji(for: code)) \(code)",
                        isSelected: localVM.selectedCountry == code
                    ) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            localVM.selectedCountry = code
                            localVM.selectedGroup = nil
                        }
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Level 1: Country grid

    private var countryGrid: some View {
        let countries = localVM.countryGroups(from: viewModel.channels, isPremium: entitlements.isPremium)
        return VStack(alignment: .leading, spacing: 16) {
            // Stats header
            HStack(spacing: 16) {
                statBadge(
                    value: "\(countries.count)",
                    label: "Regions",
                    icon: "globe"
                )
                statBadge(
                    value: "\(countries.reduce(0) { $0 + $1.totalChannels })",
                    label: "Channels",
                    icon: "tv"
                )
                statBadge(
                    value: "\(countries.reduce(0) { $0 + $1.categories.count })",
                    label: "Categories",
                    icon: "square.grid.2x2"
                )
            }
            .padding(.horizontal)

            // Country cards — full width, 2 columns on wider screens
            let cols = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
            LazyVGrid(columns: cols, spacing: 10) {
                ForEach(countries) { country in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            localVM.selectedCountry = country.id
                        }
                    } label: {
                        countryCard(country)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
    }

    private func countryCard(_ country: LiveTVViewModel.CountryGroup) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top: flag + name
            HStack(spacing: 10) {
                Text(country.flag)
                    .font(.system(size: 28))

                VStack(alignment: .leading, spacing: 2) {
                    Text(country.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.saTextPrimary)
                        .lineLimit(1)

                    Text("\(country.categories.count) categories")
                        .font(.caption2)
                        .foregroundStyle(Color.saTextSecondary)
                }

                Spacer(minLength: 0)

                Text("\(country.totalChannels)")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Color.saAccent)
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 10)

            // Bottom: preview of top category names
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(country.categories.prefix(4)) { cat in
                        Text(cat.cleanName)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color.saTextSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.saBackground.opacity(0.6))
                            .clipShape(Capsule())
                    }
                    if country.categories.count > 4 {
                        Text("+\(country.categories.count - 4)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.saAccent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.saAccent.opacity(0.1))
                            .clipShape(Capsule())
                    }
                }
                .padding(.horizontal, 14)
            }
            .padding(.bottom, 12)
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.saCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.04), lineWidth: 1)
        )
    }

    private func statBadge(value: String, label: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(Color.saAccent)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.saTextPrimary)
                Text(label)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.saTextSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.saCard.opacity(0.6))
        )
    }

    // MARK: - Level 2: Category list within country

    private func categoryList(for countryCode: String) -> some View {
        let categories = localVM.categoriesForCountry(
            countryCode, from: viewModel.channels, isPremium: entitlements.isPremium
        )
        return LazyVStack(spacing: 6) {
            ForEach(categories) { cat in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        localVM.selectedGroup = cat.id
                    }
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(categoryColor(for: cat.cleanName).opacity(0.12))
                                .frame(width: 40, height: 40)
                            Image(systemName: categoryIcon(for: cat.cleanName))
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(categoryColor(for: cat.cleanName))
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(cat.cleanName)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Color.saTextPrimary)
                                .lineLimit(1)
                            Text("\(cat.channels.count) channels")
                                .font(.caption2)
                                .foregroundStyle(Color.saTextSecondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption2.bold())
                            .foregroundStyle(Color.saTextSecondary.opacity(0.4))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.saCard.opacity(0.5))
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Category visual helpers

    private func categoryIcon(for name: String) -> String {
        let lower = name.lowercased()
        if lower.contains("sport") || lower.contains("football") || lower.contains("soccer") ||
           lower.contains("nfl") || lower.contains("nba") || lower.contains("nhl") ||
           lower.contains("mlb") || lower.contains("ufc") || lower.contains("rugby") ||
           lower.contains("tennis") || lower.contains("formula") || lower.contains("racing") ||
           lower.contains("hockey") || lower.contains("league") || lower.contains("championship") ||
           lower.contains("masters") || lower.contains("golf") || lower.contains("cricket") ||
           lower.contains("dazn") || lower.contains("espn") || lower.contains("tnt sport") {
            return "sportscourt"
        }
        if lower.contains("ppv") || lower.contains("event") { return "ticket" }
        if lower.contains("news") { return "newspaper" }
        if lower.contains("kids") || lower.contains("cartoon") || lower.contains("family") { return "figure.2.and.child.holdinghands" }
        if lower.contains("movie") || lower.contains("cinema") || lower.contains("film") ||
           lower.contains("cine") || lower.contains("24/7") { return "film" }
        if lower.contains("music") || lower.contains("video") { return "music.note" }
        if lower.contains("documentary") || lower.contains("discovery") || lower.contains("docs") { return "doc.text.image" }
        if lower.contains("netflix") || lower.contains("disney") || lower.contains("prime") ||
           lower.contains("hbo") || lower.contains("apple") || lower.contains("paramount") ||
           lower.contains("peacock") || lower.contains("hulu") || lower.contains("roku") ||
           lower.contains("tubi") || lower.contains("sling") || lower.contains("max") ||
           lower.contains("iplayer") || lower.contains("itv") || lower.contains("now tv") ||
           lower.contains("ondemand") || lower.contains("play") || lower.contains("sky store") { return "play.tv" }
        if lower.contains("adult") { return "eye.slash" }
        if lower.contains("vip") { return "crown" }
        if lower.contains("ultra") || lower.contains("raw") || lower.contains("dolby") { return "sparkles" }
        return "tv"
    }

    private func categoryColor(for name: String) -> Color {
        let lower = name.lowercased()
        if lower.contains("sport") || lower.contains("football") || lower.contains("soccer") ||
           lower.contains("nfl") || lower.contains("nba") || lower.contains("nhl") ||
           lower.contains("league") || lower.contains("ufc") || lower.contains("dazn") ||
           lower.contains("espn") || lower.contains("tnt") { return .green }
        if lower.contains("ppv") || lower.contains("event") { return .orange }
        if lower.contains("news") { return .blue }
        if lower.contains("kids") || lower.contains("cartoon") { return .pink }
        if lower.contains("movie") || lower.contains("cinema") || lower.contains("film") { return .purple }
        if lower.contains("vip") { return .yellow }
        return Color.saAccent
    }

    // MARK: - Level 3: Channel list (when category selected)

    private func channelGrid(channels: [Channel]) -> some View {
        LazyVStack(spacing: 6) {
            ForEach(channels) { channel in
                Button {
                    selectedChannel = channel
                    showPlayer = true
                } label: {
                    HStack(spacing: 12) {
                        // Logo
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.saCard)
                                .frame(width: 46, height: 46)

                            if let logoURL = channel.logoURL, let url = URL(string: logoURL) {
                                KFImage(url)
                                    .resizable()
                                    .placeholder {
                                        Image(systemName: "tv")
                                            .foregroundStyle(Color.saAccent.opacity(0.4))
                                    }
                                    .scaledToFit()
                                    .frame(width: 30, height: 30)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            } else {
                                Image(systemName: "tv")
                                    .font(.body)
                                    .foregroundStyle(Color.saAccent.opacity(0.5))
                            }
                        }

                        // Channel info
                        VStack(alignment: .leading, spacing: 3) {
                            Text(channel.name)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Color.saTextPrimary)
                                .lineLimit(1)

                            if let prog = channel.currentProgram {
                                Text(prog.title)
                                    .font(.caption)
                                    .foregroundStyle(Color.saAccent)
                                    .lineLimit(1)
                            }
                        }

                        Spacer()

                        // Live dot + play
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 6, height: 6)

                            Image(systemName: "play.circle.fill")
                                .font(.title3)
                                .foregroundStyle(Color.saAccent.opacity(0.6))
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(selectedChannel?.id == channel.id
                                  ? Color.saAccent.opacity(0.1)
                                  : Color.saCard.opacity(0.4))
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Search results

    private var searchResults: some View {
        Group {
            if filteredChannels.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 40))
                        .foregroundStyle(Color.saTextSecondary.opacity(0.5))
                    Text("No results for \"\(localVM.searchText)\"")
                        .font(.callout)
                        .foregroundStyle(Color.saTextSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredChannels) { channel in
                            ChannelCardView(
                                channel: channel,
                                isSelected: selectedChannel?.id == channel.id
                            ) {
                                selectedChannel = channel
                                showPlayer = true
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
                .background(Color.saBackground)
            }
        }
    }

    // MARK: - Upgrade bar

    private var upgradeBar: some View {
        HStack(spacing: 14) {
            Image(systemName: "sparkles")
                .foregroundStyle(Color.saAccent)
            Text("Upgrade for unlimited channels")
                .font(.subheadline)
                .foregroundStyle(Color.saTextSecondary)
            Spacer()
            Button("StreamArc+") { showPaywall = true }
                .buttonStyle(AccentButtonStyle())
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(Color.saCard.opacity(0.8))
    }
}

// MARK: - Channel Tile (compact card)

struct ChannelTile: View {
    let channel: Channel
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                // Logo circle
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.saAccent.opacity(0.2) : Color.saCard)
                        .frame(width: 64, height: 64)

                    if let logoURL = channel.logoURL, let url = URL(string: logoURL) {
                        KFImage(url)
                            .resizable()
                            .placeholder {
                                Image(systemName: "tv")
                                    .foregroundStyle(Color.saAccent.opacity(0.5))
                            }
                            .scaledToFit()
                            .frame(width: 40, height: 40)
                            .clipShape(Circle())
                    } else {
                        Image(systemName: "tv")
                            .font(.title3)
                            .foregroundStyle(Color.saAccent.opacity(0.6))
                    }

                    // Live indicator
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                        .offset(x: 24, y: -24)
                }

                Text(channel.name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isSelected ? Color.saAccent : Color.saTextPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: 80)

                if let prog = channel.currentProgram {
                    Text(prog.title)
                        .font(.system(size: 9))
                        .foregroundStyle(Color.saTextSecondary)
                        .lineLimit(1)
                        .frame(width: 80)
                }
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Channel Card (list style for search results)

private struct ChannelCardView: View {
    let channel: Channel
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                // Logo
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.saCard)
                        .frame(width: 50, height: 50)

                    if let logoURL = channel.logoURL, let url = URL(string: logoURL) {
                        KFImage(url)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 32, height: 32)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    } else {
                        Image(systemName: "tv")
                            .font(.title3)
                            .foregroundStyle(Color.saAccent.opacity(0.6))
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(channel.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.saTextPrimary)
                        .lineLimit(1)

                    if let prog = channel.currentProgram {
                        Text(prog.title)
                            .font(.caption)
                            .foregroundStyle(Color.saAccent)
                            .lineLimit(1)
                    } else if !channel.groupTitle.isEmpty {
                        Text(channel.groupTitle)
                            .font(.caption)
                            .foregroundStyle(Color.saTextSecondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Image(systemName: "play.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Color.saAccent.opacity(0.7))
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? Color.saAccent.opacity(0.1) : Color.saCard.opacity(0.6))
            )
        }
        .buttonStyle(.plain)
    }
}
