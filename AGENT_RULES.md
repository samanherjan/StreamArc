# StreamArc — AI Agent Rules & Coding Standards

> **Read this file BEFORE making any code changes.**
> This is a multi-platform SwiftUI app targeting **iOS, iPadOS, macOS, and tvOS** from a single shared codebase.
> Every change you make compiles for ALL four platforms. Breaking one platform to fix another is never acceptable.

---

## 1. Project Architecture

```
StreamArc/
├── App/
│   ├── iOS/          # iOS-only entry point & Info.plist
│   ├── tvOS/         # tvOS-only entry point & Info.plist
│   ├── macOS/        # macOS-only entry point & Info.plist
│   └── Shared/       # AppEnvironment, SettingsStore (all platforms)
├── Core/
│   ├── Models/
│   │   └── Profile.swift  # SwiftData @Model (must stay in app target)
│   └── Storage/           # SwiftData @Model types & managers (must stay in app target)
│       ├── FavoritesManager.swift
│       └── WatchHistoryManager.swift
├── Features/
│   ├── Home/         # HomeView, HomeViewModel
│   ├── LiveTV/       # LiveTVView, EPGGridView
│   ├── VOD/          # MoviesView, SeriesView, MovieDetailView, SeriesDetailView
│   ├── Player/       # PlayerView, PlayerViewModel, TrailerPlayerView
│   ├── Search/       # SearchView, SearchViewModel
│   ├── Settings/     # SettingsView, ParentalLockView
│   ├── Profiles/     # ProfilesView, ProfileDetailView
│   └── Onboarding/   # OnboardingView, AddProfileView
├── Shared/
│   ├── Components/   # Reusable UI: CategoryChip, PosterCardView, LoadingView, etc.
│   └── Extensions/   # Color+Theme, View+Platform
├── Monetization/     # StoreManager, EntitlementManager, PaywallView
├── Ads/              # AdsManager, BannerAdView, InterstitialAdManager
├── Resources/        # Assets, Preview Content
└── LocalPackages/
    └── StreamArcCore/    # Local Swift package (see below)
```

### StreamArcCore Package (`LocalPackages/StreamArcCore/`)
Platform-agnostic code extracted into a local Swift package. All 3 app targets depend on it.

```
StreamArcCore/Sources/
├── Models/       # Channel, VODItem, Series, Episode, Season, SourceType, EPGProgram
├── Networking/   # M3UParser, XtreamClient, StalkerClient, Enigma2Client, TMDBClient, EPGParser
└── Extensions/   # Array+Chunked
```

**Rules:**
- Every file in Features/, Shared/, Monetization/, App/ that uses Core types MUST have `import StreamArcCore`
- SwiftData `@Model` types (Profile, FavoriteItem, WatchHistoryEntry) **cannot** live in the package (SwiftData macros require Xcode compilation). They stay in `StreamArc/Core/`.
- When adding new models or networking clients, add them to the **package**, not to `StreamArc/Core/`
- All types in the package are `public`

---

## 2. Platform Compatibility Rules (CRITICAL)

### APIs That Are NOT Available on tvOS
These MUST be wrapped in `#if !os(tvOS)` or `#if os(iOS)`:

| API | Platforms | Guard |
|-----|-----------|-------|
| `.navigationBarTitleDisplayMode(_:)` | iOS only | `#if !os(tvOS)` |
| `.statusBarHidden(_:)` | iOS only | `#if !os(tvOS)` |
| `WKWebView` | iOS, macOS | `#if !os(tvOS)` |
| `AVPictureInPictureController` | iOS, macOS | `#if !os(tvOS)` |
| `Slider` | iOS, macOS | `#if !os(tvOS)` |
| `UIApplication.shared` (for opening URLs) | iOS, tvOS | Not on macOS — use `NSWorkspace.shared.open()` |
| `AVRoutePickerView` (AirPlay) | iOS: `UIViewRepresentable`, macOS: `NSViewRepresentable` | `#if os(iOS)` / `#if os(macOS)` |
| `GoogleMobileAds` / `GADBannerView` | iOS, macOS | `#if !os(tvOS)` (tvOS target has no GoogleMobileAds dependency) |

### APIs That ARE Available on tvOS but Behave Differently
| API | Note |
|-----|------|
| `.searchable()` | Available on tvOS 17+, works fine |
| `.sheet()` | Renders as a TINY overlay on tvOS. Use `.fullScreenCover()` instead |
| `.buttonStyle(.plain)` | Removes ALL focus feedback on tvOS — NEVER use directly |
| `VideoPlayer` (SwiftUI) | Works but has no Siri Remote transport controls — use `AVPlayerViewController` on tvOS |

### The Golden Rule
**Before using ANY UIKit/AppKit API in a SwiftUI view, ask: "Does this exist on all 4 platforms?"**
If not, wrap it in the appropriate `#if os()` guard.

---

## 3. UI Patterns by Platform

### Button Styles
```swift
// ✅ CORRECT — use this everywhere
.cardFocusable()
// This applies .buttonStyle(.card) on tvOS (focus lift + shadow)
// and .buttonStyle(.plain) on iOS/macOS

// ❌ WRONG — kills tvOS focus feedback
.buttonStyle(.plain)
```

### Presenting Detail Views
```swift
// ✅ CORRECT
#if os(tvOS)
.fullScreenCover(item: $selectedItem) { item in
    DetailView(item: item)
}
#else
.sheet(item: $selectedItem) { item in
    DetailView(item: item)
}
#endif

// ❌ WRONG — sheet is unusably small on Apple TV
.sheet(item: $selectedItem) { ... }
```

### Navigation Bar Title Display Mode
```swift
// ✅ CORRECT
#if !os(tvOS)
.navigationBarTitleDisplayMode(.inline)
#endif

// ❌ WRONG — compile error on tvOS
.navigationBarTitleDisplayMode(.inline)
```

### Player View
- **tvOS**: Use `AVPlayerViewController` via `UIViewControllerRepresentable` — gives native Siri Remote controls, scrubbing, and transport bar for free
- **iOS/macOS**: Use `VideoPlayer` with custom overlay controls
- These are already split in `PlayerView.swift` using `#if os(tvOS)` / `#if !os(tvOS)`

### AirPlay Button
- **iOS**: `UIViewRepresentable` wrapping `AVRoutePickerView`
- **macOS**: `NSViewRepresentable` wrapping `AVRoutePickerView`
- **tvOS**: Not needed (AirPlay is system-level on Apple TV)

---

## 4. Playback & Streaming Rules

### Stream URL Handling
1. **Always strip `"ffmpeg "` prefix** — Stalker/MAG portals prepend this to stream URLs
2. **Stalker sources require URL resolution** — Call `StalkerClient.resolveStreamURL(cmd:)` before creating an `AVPlayerItem`. The raw `cmd` string from the channel list is NOT a playable URL.
3. **Use `AVPlayerItem(url:)` directly** — Do NOT use `AVURLAsset` with `AVURLAssetHTTPHeaderFieldsKey` (private API, causes "resource unavailable" on real devices)
4. **Do NOT call `asset.load(.isPlayable)`** before playing — many live IPTV streams (HLS/TS) fail this check even though they play fine

### PlayerViewModel Source Configuration
Before playing any stream, call `viewModel.vm.configureSource(profile:)` with the active `Profile` so the player knows:
- Whether to resolve Stalker URLs
- What source type the stream came from

---

## 5. Theme & Design System

### Colors (defined in `Color+Theme.swift`)
| Token | Hex | Usage |
|-------|-----|-------|
| `Color.saBackground` | `#0A0A0F` | Root backgrounds |
| `Color.saSurface` | `#141420` | Elevated surfaces |
| `Color.saCard` | `#1C1C2E` | Cards, list rows |
| `Color.saAccent` | `#5E5CE6` | Buttons, highlights, interactive elements |
| `Color.saTextPrimary` | White | Titles, headings |
| `Color.saTextSecondary` | `#8E8E9A` | Subtitles, captions |
| `Color.saError` | `#FF453A` | Error states |

### tvOS 10-Foot UI
- tvOS is viewed from ~10 feet away on a big screen
- Fonts, icons, and touch targets should be LARGER than iOS
- Use `.cardFocusable()` on all buttons for proper focus feedback
- Use `.tvFocusScale()` modifier for custom focus animations
- Hero images / posters should be larger (use `frame(height: 300+)` vs iOS `200`)

---

## 6. Dependencies

| Package | Platforms | Notes |
|---------|-----------|-------|
| `Kingfisher` | iOS, tvOS, macOS | Image loading/caching. Used everywhere for poster images. |
| `GoogleMobileAds` | iOS, macOS ONLY | AdMob banners & interstitials. **NOT available on tvOS.** All ad code must be inside `#if !os(tvOS)`. |
| `StoreKit` (system) | All | In-app purchases, entitlement checking |

---

## 7. Data Flow

```
Profile (SwiftData) → HomeViewModel.load(profile:) → Client (M3U/Xtream/Stalker/Enigma2)
                                                        ↓
                                          channels: [Channel]
                                          vodItems: [VODItem]
                                          series:   [Series]
                                                        ↓
                                          Views observe HomeViewModel
```

- `HomeViewModel` is the single source of truth for loaded content
- It's passed to child views: `LiveTVView(viewModel:)`, `MoviesView(viewModel:)`, etc.
- Local ViewModels (`LiveTVViewModel`, `VODViewModel`) handle filtering/search/UI state only
- `PlayerViewModel` is independent — created per-player instance via `PlayerViewModelBridge`

---

## 8. Monetization / Free Tier

- Free users: 200 channel cap, 10 favorites cap, ads shown, series locked
- Premium (`EntitlementManager.isPremium`): unlimited everything, no ads, PiP, trailers
- Always check `entitlements.isPremium` before gating features
- Ads code is wrapped in `#if !os(tvOS)` — no ads on Apple TV

---

## 9. Testing Checklist

Before considering any change complete, mentally verify:

- [ ] Does this compile for **iOS**? (no tvOS/macOS-only APIs unguarded)
- [ ] Does this compile for **tvOS**? (no `navigationBarTitleDisplayMode`, `WKWebView`, `GoogleMobileAds`, etc.)
- [ ] Does this compile for **macOS**? (no `UIApplication`, `UIView` without `#if os(iOS)`)
- [ ] Are all buttons using `.cardFocusable()` instead of `.buttonStyle(.plain)`?
- [ ] Are detail view presentations using `.fullScreenCover` on tvOS?
- [ ] If touching Player code: does Stalker URL resolution still work?
- [ ] If adding new dependencies: are they available on all targeted platforms?

---

## 10. Common Patterns

### Adding a New Feature View
```swift
struct MyNewView: View {
    var body: some View {
        NavigationStack {
            content
                .background(Color.saBackground.ignoresSafeArea())
#if !os(tvOS)
                .navigationBarTitleDisplayMode(.inline)
#endif
        }
    }
}
```

### Adding a New Button
```swift
Button("Action") { doSomething() }
    .cardFocusable()  // NOT .buttonStyle(.plain)
```

### Presenting a Detail View
```swift
#if os(tvOS)
.fullScreenCover(item: $selected) { item in MyDetailView(item: item) }
#else
.sheet(item: $selected) { item in MyDetailView(item: item) }
#endif
```

### Platform-Specific Code Block
```swift
#if os(tvOS)
// tvOS-only code
#elseif os(macOS)
// macOS-only code
#else
// iOS/iPadOS code
#endif
```

---

**Last updated: April 28, 2026**
