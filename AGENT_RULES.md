# StreamArc — AI Agent Rules & Coding Standards

> **Read this file BEFORE making any code changes.**
> This is a multi-platform SwiftUI app targeting **iOS, iPadOS, macOS, and tvOS** from a single shared codebase.
> Every change you make compiles for ALL four platforms. Breaking one platform to fix another is never acceptable.

---

## 0. Test Credentials

Use these when debugging playback, testing new features, or reproducing stream-related issues.

### Stalker / MAG Portal
| Field | Value |
|-------|-------|
| Portal URL | `http://javidshahiptv.xyz/c/` |
| MAC Address | `00:1A:79:F6:7E:02` |
| Server base (derived) | `http://javidshahiptv.xyz/server/` |
| Auth endpoint | `GET /server/load.php?type=stb&action=handshake&token=` |

**Behaviour notes confirmed by live testing:**
- `get_all_channels` returns live-TV cmds as `ffmpeg http://javidshahiptv.xyz:80/play/live.php?mac=...&stream=<id>&play_token=<token>` — these are **already playable** without calling `create_link`.
- Calling `create_link` on a live-TV URL **breaks it** — the server returns `stream=` empty.
- VOD cmds are **base64-encoded JSON** blobs (e.g. `eyJ0eXBlIjoibW92aWUiLC...`), not URLs. They decode to `{"type":"movie","stream_id":"...","target_container":["mkv"]}`.
- VOD resolution requires `type=vod&action=create_link` — **not** `type=itv`.
- The server validates the `mac` cookie on every request. The `Authorization: Bearer <token>` header is required after the handshake.

**Quick curl test (two-step auth then channel fetch):**
```bash
TOKEN1=$(curl -s "http://javidshahiptv.xyz/server/load.php?type=stb&action=handshake&token=" \
  -H "User-Agent: Mozilla/5.0 (QtEmbedded; U; Linux; C) AppleWebKit/533.3 (KHTML, like Gecko) MAG200 stbapp ver: 2.18.27 serial: 001A79F67E02 SDK/4.4.17" \
  -H "Cookie: mac=00%3A1A%3A79%3AF6%3A7E%3A02; stb_lang=en; timezone=UTC" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['js']['token'])")

TOKEN2=$(curl -s "http://javidshahiptv.xyz/server/load.php?type=stb&action=handshake&token=$TOKEN1" \
  -H "User-Agent: Mozilla/5.0 (QtEmbedded; U; Linux; C) AppleWebKit/533.3 (KHTML, like Gecko) MAG200 stbapp ver: 2.18.27 serial: 001A79F67E02 SDK/4.4.17" \
  -H "Cookie: mac=00%3A1A%3A79%3AF6%3A7E%3A02; stb_lang=en; timezone=UTC" \
  -H "Authorization: Bearer $TOKEN1" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['js']['token'])")

# Fetch first 3 channels
curl -s "http://javidshahiptv.xyz/server/load.php?type=itv&action=get_all_channels&p=1&items_per_page=3" \
  -H "Authorization: Bearer $TOKEN2" \
  -H "Cookie: mac=00%3A1A%3A79%3AF6%3A7E%3A02; stb_lang=en; timezone=UTC" \
  | python3 -c "import sys,json; [print(c['name'],'|',c['cmd']) for c in json.load(sys.stdin)['js']['data']]"
```

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
- **CRITICAL tvOS rule**: Never assign `vc.player` inside `makeUIViewController`. `makeUIViewController` is called during the initial SwiftUI layout pass when UIKit applies a `_UITemporaryLayoutWidth = 0` constraint. On tvOS the media server (`FigApplicationStateMonitor`) refuses to initialise the pipeline against a zero-size surface → `AVFoundationErrorDomain -11828`. Always assign the player in `updateUIViewController` (called post-layout with the real frame). Always render `AVPlayerViewControllerRepresentable` unconditionally (not inside `if let player`), so the VC is in the hierarchy at full size before the player is assigned. On tvOS, do NOT call `avPlayer.play()` in `startPlayback` — trigger it from `updateUIViewController` after the player is attached to the VC.

### AirPlay Button
- **iOS**: `UIViewRepresentable` wrapping `AVRoutePickerView`
- **macOS**: `NSViewRepresentable` wrapping `AVRoutePickerView`
- **tvOS**: Not needed (AirPlay is system-level on Apple TV)

---

## 4. Playback & Streaming Rules

### Stream URL Handling
1. **Always strip `"ffmpeg "` prefix** — Stalker/MAG portals prepend this to stream URLs. Do this at the earliest possible point (parsing time, not play time).
2. **Always strip pipe-style HTTP headers** — Many IPTV M3U playlists append HTTP headers to URLs using a pipe separator: `http://server/stream.mp4|User-Agent=VLC&Referer=http://server/`. `URL(string:)` in Swift accepts these strings but AVFoundation sends the pipe and everything after it as part of the HTTP path, causing "resource not available" on every stream. Strip everything from `|` onwards before constructing a `URL`. This is handled in `StreamResolver.resolve()` — do NOT bypass it.
3. **Stalker live-TV channels have pre-embedded play_tokens** — The `cmd` field returned by `get_all_channels` already contains a valid, playable HTTP URL with `play_token` embedded. **Do NOT call `create_link` on it** — this portal's `create_link` overwrites the `stream=` parameter with an empty value, producing a broken URL.
4. **Stalker VOD uses base64-encoded JSON cmds** — VOD `cmd` fields are base64-encoded JSON blobs (e.g. `eyJ0eXBlIjoibW92...`), not URLs. They MUST be resolved via `type=vod&action=create_link`, NOT `type=itv`. Using `type=itv` for VOD returns a broken live-TV URL.
5. **Always validate `create_link` responses** — Check that the resolved URL does not contain `stream=&` (empty stream parameter) or other obviously broken patterns before passing it to AVPlayer. Fall back to `StalkerError.streamResolutionFailed` rather than silently playing a broken URL.
6. **Never swallow Stalker resolution errors** — `StreamResolver.resolve()` must NOT catch Stalker auth/resolution errors and fall back to the raw cmd string. A raw Stalker cmd is either a base64 JSON blob or an opaque token — neither is a valid HTTP URL. Passing a schemeless blob to AVFoundation produces "Cannot Open" on every attempt. Let the error propagate so `PlayerViewModel` can show a meaningful message.
    7. **Always validate the resolved URL has an http/https scheme** — Use `validatedHTTPURL(from:)` (or an equivalent guard) before returning any URL from `StreamResolver`. A relative/schemeless URL silently passes `URL(string:)` but fails immediately in AVFoundation.
    8. **Use `AVURLAsset` with `preferPreciseDurationAndTiming: false`** — For large MKV/TS HTTP streams, AVFoundation by default tries to seek to the end of the file to compute precise duration. This fails for streams that aren't pre-indexed or are very large (2+ GB). Always use `AVURLAsset(url:, options: [AVURLAssetPreferPreciseDurationAndTimingKey: false])` to allow playback to start without duration pre-computation.
    9. **Use `AVURLAssetHTTPCookiesKey` to deliver auth cookies to AVFoundation for Stalker streams** — AVFoundation's media server process (`mediaserverd`) does NOT share `HTTPCookieStorage` with the app process. The public API for injecting cookies into `mediaserverd` is `AVURLAssetHTTPCookiesKey` (value type: `[HTTPCookie]`, available iOS 8+, tvOS 9+, macOS 10.15+). Set it in `assetOptions` before creating the `AVURLAsset`: `assetOptions[AVURLAssetHTTPCookiesKey] = cookies`. **Do NOT use `AVURLAssetHTTPHeaderFieldsKey`** — this symbol does not exist in the public SDK and causes a compile error on all platforms.
    10. **Use `StalkerResourceLoaderDelegate` for Stalker stream playback** — Stalker/MAG stream servers validate the `User-Agent` header and reject requests from AVFoundation's default `AppleCoreMedia/...` UA, returning an HTML error page → `-11828`. Since there is no public API to set custom HTTP headers on `AVURLAsset`, we use an `AVAssetResourceLoaderDelegate` with a custom URL scheme (`stalkerhttp://` / `stalkerhttps://`). The delegate intercepts loading requests, restores the real `http(s)` scheme, injects the MAG User-Agent + cookies, fetches data via URLSession, and delivers it back to AVFoundation. The delegate (`StalkerResourceLoaderDelegate`) must be retained for the lifetime of playback (stored in `PlayerViewModel.stalkerLoaderDelegate`). This approach also handles byte-range requests for seeking in large MKV/MP4 files.
    10. **Never byte-probe Stalker VOD URLs** — Stalker `play_token` values are **single-use**. Making any HTTP request (even a `Range: bytes=0-7` probe) consumes the token. When AVFoundation subsequently uses the same URL with the now-invalidated token, the server returns an HTML error page → -11828. Skip the byte probe for Stalker streams (`sourceType == .stalker`) and use URL-pattern MIME hints instead (`.mkv` in URL → `video/x-matroska`, `.ts` → `video/mp2t`, etc.).
    11. **Use `URL(string:)` with percent-encoding fallback** — `URL(string:)` returns `nil` for URLs with unencoded spaces, causing silent playback failures. Always try `URL(string: raw) ?? URL(string: raw.addingPercentEncoding(...))` and show a user-visible error if both fail. Never `guard let url = URL(string: ...) else { return }` without setting an error state.
    12. **Do NOT call `asset.load(.isPlayable)`** before playing — many live IPTV streams (HLS/TS) fail this check even though they play fine.
    13. **Always `import AVFoundation` unconditionally** — Do not wrap `import AVFoundation` in `#if !os(macOS)`. AVFoundation is a first-class framework on macOS and must be explicitly imported for AVFoundation symbols (e.g. `AVURLAssetHTTPCookiesKey`) to be in scope on all platforms.
### App Transport Security (ATS)
- Use **only `NSAllowsArbitraryLoads: true`** in `NSAppTransportSecurity`. Do NOT add `NSAllowsArbitraryLoadsForMedia`, `NSAllowsArbitraryLoadsInWebContent`, or any other specific ATS key alongside it.
- **Critical iOS 10+ rule**: When ANY specific ATS key (`NSAllowsArbitraryLoadsForMedia`, `NSAllowsArbitraryLoadsInWebContent`) is present in the plist, iOS completely **ignores** `NSAllowsArbitraryLoads`. Adding a "more specific" key actually makes ATS MORE restrictive, not less.
- ATS config lives in **`project.yml`** (`info.properties` for each target). Do NOT edit Info.plist files directly — `xcodegen generate` regenerates them from `project.yml` and will overwrite any manual changes.
- Correct ATS config in `project.yml`:
  ```yaml
  NSAppTransportSecurity:
    NSAllowsArbitraryLoads: true
  ```
  Nothing else. No other keys under `NSAppTransportSecurity`.

### Package Management (XcodeGen)
- **`project.yml` is the single source of truth** for the Xcode project. Never edit `project.pbxproj` directly.
- Any Swift package listed as a `dependency` in `project.yml` MUST also be declared in the top-level `packages:` section with a `url:` and `from:` (or `exactVersion:`). XcodeGen silently drops dependencies that reference undeclared packages — this shows up as "Missing package product" errors at build time.
- After any change to `project.yml`, run `xcodegen generate` then `xcodebuild -resolvePackageDependencies`.
- **Commit `Package.resolved`** — located at `StreamArc.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`. This pins every dependency to an exact version and prevents "Missing package product" errors on clean checkouts or CI.

### PlayerViewModel Source Configuration
- Before playing any stream, call `viewModel.vm.configureSource(profile:)` with the active `Profile` so the player knows whether to resolve Stalker URLs and what source type the stream came from.
- Use `.task { load() }` (not `.onAppear { load() }`) to trigger playback setup — `.task` runs after SwiftUI has settled the environment, ensuring `@Query` results (including the active `Profile`) are populated. `.onAppear` fires before `@Query` finishes, leaving `activeProfile` nil and skipping `configureSource`.
- **Always pass the profile explicitly to `PlayerView`** — Do NOT rely on `PlayerView`'s internal `@Query` for `Profile` when launching from a VOD detail screen. SwiftData `@Query` results are NOT guaranteed to be populated when `.task` fires (race condition). If `activeProfile` is nil, `configureSource` is skipped, `sourceType` stays `.m3u`, and Stalker VOD base64 cmds are passed raw to AVFoundation → **"Cannot Open"** error. The correct pattern:
  ```swift
  // In the presenting view — add @Query here, not only inside PlayerView
  @Query(filter: #Predicate<Profile> { $0.isActive == true })
  private var activeProfiles: [Profile]
  private var activeProfile: Profile? { activeProfiles.first }

  // Pass it explicitly — exactly ONCE. Duplicate labels (e.g. profile: x, profile: x)
  // are a compile error in Swift and must never be written.
  PlayerView(streamURL: item.streamURL, title: item.title, profile: activeProfile)
  ```
  `PlayerView` accepts `var profile: Profile? = nil` and uses `(profile ?? activeProfile)` in `load()` so the explicitly-passed value always wins over the internal query.

### Stalker URL Resolution — Decision Tree
```
channel.streamURL (after ffmpeg strip)
        │
        ├─ starts with "http://" or "https://"?
        │       └─ YES → use directly (play_token already embedded)
        │
        ├─ looks like base64 JSON (no scheme, only base64 chars)?
        │       └─ YES → call type=vod&action=create_link
        │
        └─ other cmd string
                └─ call type=itv&action=create_link
                   then validate: stream= must not be empty
```

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
| `YouTubePlayerKit` | iOS, macOS | YouTube trailer playback. Must be declared in BOTH `packages:` and target `dependencies:` in `project.yml`. |
| `StoreKit` (system) | All | In-app purchases, entitlement checking |

### Adding a New Package
1. Add to `packages:` section in `project.yml` with `url:` and `from:`
2. Add to each relevant target's `dependencies:` list in `project.yml`
3. Run `xcodegen generate`
4. Run `xcodebuild -resolvePackageDependencies`
5. Commit the updated `Package.resolved`

Skipping step 1 while doing step 2 causes XcodeGen to silently drop the dependency, resulting in "Missing package product" build errors.

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
- [ ] If touching Player code: does Stalker URL resolution still work for both live TV AND VOD?
- [ ] If touching Player code: does `configureSource` get called BEFORE `setup`? Is `.task` used instead of `.onAppear`?
- [ ] If touching Stalker playback: are the `mac`, `stb_lang`, and `timezone` cookies injected into `HTTPCookieStorage.shared` via `injectStalkerCookies(macAddress:host:)` before creating the `AVURLAsset`? (Without this, the server returns HTML instead of the stream → -11828 on every attempt.)
- [ ] If touching Stalker playback: is `StalkerResourceLoaderDelegate` used with a custom URL scheme (`stalkerhttp://`) to inject MAG User-Agent + cookies? (AVFoundation's default User-Agent is rejected by Stalker servers → -11828.)
- [ ] If touching Stalker playback: is the byte-probe (`detectMIMEType`) skipped for Stalker sources? (`play_token` is single-use — probing consumes it before AVFoundation can use it.)
- [ ] If adding a new `PlayerView` call site: is `profile: activeProfile` passed explicitly **exactly once**? Does the presenting view have `@Query` for the active profile? (Duplicate `profile:` argument labels cause a compile error — Swift does not allow the same argument label twice in one call.)
- [ ] If adding new dependencies: declared in BOTH `packages:` AND target `dependencies:` in `project.yml`?
- [ ] After editing `project.yml`: run `xcodegen generate` + `xcodebuild -resolvePackageDependencies`?
- [ ] Does `NSAppTransportSecurity` in `project.yml` contain **only** `NSAllowsArbitraryLoads: true` with no other child keys?
- [ ] Do all stream URLs pass through `StreamResolver.resolve()` (pipe stripping, ffmpeg stripping, encoding)?
- [ ] Does every `URL(string:)` call for stream URLs have a percent-encoding fallback and a visible error on failure?

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

**Last updated: April 29, 2026**
