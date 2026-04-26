import Foundation

// Manages interstitial ad load/show lifecycle.
// Enforces a minimum 10-minute interval and triggers after 3 tab switches.
@MainActor
@Observable
final class InterstitialAdManager {

    private let entitlementManager: EntitlementManager
    private var lastShownAt: Date?
    private var tabSwitchCount = 0

    private let minimumInterval: TimeInterval = 600   // 10 minutes
    private let tabSwitchThreshold = 3

#if DEBUG
    private let adUnitID = "ca-app-pub-3940256099942544/4411468910"
#else
    private let adUnitID = Bundle.main.infoDictionary?["GADAdUnitIDInterstitial"] as? String
        ?? "ca-app-pub-3940256099942544/4411468910"
#endif

    init(entitlementManager: EntitlementManager) {
        self.entitlementManager = entitlementManager
    }

    // Call this on each tab switch event.
    func recordTabSwitch() {
        guard !entitlementManager.isPremium else { return }
        tabSwitchCount += 1
        if tabSwitchCount >= tabSwitchThreshold, canShowInterstitial() {
            showInterstitial()
            tabSwitchCount = 0
        }
    }

    private func canShowInterstitial() -> Bool {
        guard let last = lastShownAt else { return true }
        return Date.now.timeIntervalSince(last) >= minimumInterval
    }

    private func showInterstitial() {
#if os(tvOS)
        // AppLovin: MAInterstitialAd.showAd(from: topVC)
#elseif os(iOS)
        // AdMob: interstitial.present(fromRootViewController: topVC)
        // Load next ad immediately after showing
#endif
        lastShownAt = Date.now
    }

    func preload() {
#if os(iOS)
        // GADInterstitialAd.load(withAdUnitID: adUnitID, request: GADRequest()) { ... }
#elseif os(tvOS)
        // MAInterstitialAd(...).load()
#endif
    }
}
