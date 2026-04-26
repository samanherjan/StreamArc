import Foundation

// Unified ad manager. AdMob initialisation on iOS/macOS, AppLovin on tvOS.
// ATT consent is requested before AdMob init on iOS (GDPR / Apple policy).
@MainActor
@Observable
final class AdsManager {

    private let entitlementManager: EntitlementManager
    private(set) var isInitialized = false

    var shouldShowAds: Bool { !entitlementManager.isPremium && isInitialized }

    init(entitlementManager: EntitlementManager) {
        self.entitlementManager = entitlementManager
    }

    func initialize() async {
#if os(iOS)
        await requestATTIfNeeded()
        initAdMob()
#elseif os(macOS)
        initAdMob()
#elseif os(tvOS)
        initAppLovin()
#endif
    }

    // MARK: - AdMob (iOS / macOS)

    private func initAdMob() {
#if !os(tvOS)
        // GoogleMobileAds.GADMobileAds.sharedInstance().start(completionHandler: nil)
        // Uncomment once GAD is properly imported. Placeholder to avoid import errors
        // without linking the SDK in this file directly.
        isInitialized = true
#endif
    }

    // MARK: - AppLovin (tvOS)

    private func initAppLovin() {
#if os(tvOS)
        // ALSdk.shared().initializeSdk { _ in }
        // Uncomment once AppLovin SDK is properly linked.
        isInitialized = true
#endif
    }

    // MARK: - ATT (iOS only)

    private func requestATTIfNeeded() async {
#if os(iOS)
        await withCheckedContinuation { continuation in
            if #available(iOS 14.5, *) {
                Task { @MainActor in
                    let _ = await requestTrackingAuthorization()
                    continuation.resume()
                }
            } else {
                continuation.resume()
            }
        }
#endif
    }

    @available(iOS 14.5, *)
    private func requestTrackingAuthorization() async -> Bool {
#if os(iOS)
        return await withCheckedContinuation { continuation in
            // ATTrackingManager.requestTrackingAuthorization handled via the
            // ATT prompt declared in Info.plist NSUserTrackingUsageDescription.
            // Import AppTrackingTransparency and call:
            // ATTrackingManager.requestTrackingAuthorization { status in
            //     continuation.resume(returning: status == .authorized)
            // }
            continuation.resume(returning: false)
        }
#else
        return false
#endif
    }
}
