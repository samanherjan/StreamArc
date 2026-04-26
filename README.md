# StreamArc

A clean, modern multi-platform IPTV client for iOS, iPadOS, tvOS, and macOS — built entirely with SwiftUI and native Apple frameworks.

StreamArc **does not provide, host, or distribute any content**. It is a pure client that connects to IPTV sources you already have access to.

---

## Features

- **Live TV** — channel list with EPG (Now / Next) and a full 7-day EPG grid (tvOS)
- **Movies (VOD)** — poster grid with TMDB metadata and trailer playback
- **TV Series** — season/episode browser with TMDB trailers
- **Search** — cross-section search across Live TV, Movies, and Series
- **Multi-profile** — add multiple IPTV sources and switch between them instantly
- **AirPlay** — cast to Apple TV via AVRoutePickerView
- **Picture in Picture** — continue watching while multitasking (iOS/macOS)
- **StreamArc+** — ad-free premium tier with unlimited content and advanced features

### Supported Source Types

| Type | Description |
|------|-------------|
| **M3U / M3U8** | Remote URL or local file import |
| **Xtream Codes** | Username/password API |
| **MAG / Stalker** | Portal URL + MAC address |
| **Enigma2 / E2** | Direct Enigma2 box HTTP API |

---

## Requirements

- Xcode 16+ (Xcode 26 recommended)
- macOS 14+ (Sonoma) for the build machine
- Swift 6.0+
- Deployment targets: iOS 17.0, iPadOS 17.0, tvOS 17.0, macOS 14.0

---

## Getting Started

### 1. Clone

```bash
git clone https://github.com/samanherjan/StreamArc.git
cd StreamArc
```

### 2. Install xcodegen (if not already installed)

```bash
brew install xcodegen
```

Or download from [github.com/yonaskolb/XcodeGen/releases](https://github.com/yonaskolb/XcodeGen/releases).

### 3. Generate the Xcode project

```bash
xcodegen generate
```

### 4. Open and build

```bash
open StreamArc.xcodeproj
```

Select your target (StreamArc / StreamArc_tvOS / StreamArc_macOS) and run.

---

## TMDB API Setup

Movie and series trailers use the [TMDB API](https://www.themoviedb.org/). To enable:

1. Create a free account at [themoviedb.org](https://www.themoviedb.org/)
2. Go to **Settings → API** and generate a v3 API key
3. Open StreamArc → **Settings** → enter your API key in the **TMDB API Key** field

Without a key, the trailer button is hidden gracefully.

---

## AdMob / AppLovin Setup

StreamArc uses Google AdMob on iOS/macOS and AppLovin MAX on tvOS for the free tier.

1. Replace the placeholder App ID in `StreamArc/App/iOS/Info.plist`:
   ```xml
   <key>GADApplicationIdentifier</key>
   <string>ca-app-pub-YOUR_REAL_APP_ID~YOUR_APP_ID</string>
   ```
2. Replace test ad unit IDs in `Ads/BannerAdView.swift` and `Ads/InterstitialAdManager.swift` with your production IDs for release builds.
3. Complete AdMob / AppLovin SDK initialisation in `AdsManager.swift` (commented placeholders are provided).

---

## StoreKit Testing

The `StreamArc.storekit` configuration file defines:
- `streamarc.premium.monthly` — $4.99/month, 7-day trial
- `streamarc.premium.yearly`  — $39.99/year, 7-day trial
- `streamarc.premium.lifetime` — $29.99 one-time

To test purchases locally: **Edit Scheme → Run → Options → StoreKit Configuration → StreamArc.storekit**

---

## Branch Strategy

| Branch | Purpose |
|--------|---------|
| `main` | Stable releases |
| `develop` | Active development |
| `feature/*` | Feature branches |

---

## Architecture

```
MVVM + SwiftData + async/await

App/          — Platform-specific @main entry points (iOS / tvOS / macOS)
Core/
  Models/     — SwiftData @Model + plain Sendable structs
  Networking/ — M3UParser, XtreamClient, StalkerClient, Enigma2Client, EPGParser, TMDBClient
  Storage/    — FavoritesManager, WatchHistoryManager (SwiftData)
Features/     — Screen-level views + @Observable ViewModels
Shared/       — Reusable components, extensions, theme tokens
Monetization/ — StoreKit 2: StoreManager, EntitlementManager, PaywallView
Ads/          — AdsManager, BannerAdView (AdMob), InterstitialAdManager
```

---

## Disclaimer

StreamArc is a media player application. It does not provide, host, distribute, or endorse any IPTV content. Users are solely responsible for ensuring they have lawful access to the streams they configure in the app.

---

## License

MIT — see [LICENSE](LICENSE) for details.
