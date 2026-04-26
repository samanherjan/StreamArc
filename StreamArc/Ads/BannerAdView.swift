import SwiftUI

#if !os(tvOS)
// UIViewRepresentable wrapping GADBannerView (iOS/iPadOS/macOS-Catalyst).
// On macOS native this falls back to a placeholder since GAD is Catalyst-only.
struct BannerAdView: View {

    @Environment(AdsManager.self) private var adsManager

#if DEBUG
    static let adUnitID = "ca-app-pub-3940256099942544/2934735716"   // test ID
#else
    static let adUnitID = Bundle.main.infoDictionary?["GADAdUnitIDBanner"] as? String
        ?? "ca-app-pub-3940256099942544/2934735716"
#endif

    var body: some View {
        if adsManager.shouldShowAds {
#if os(iOS)
            GADBannerRepresentable(adUnitID: Self.adUnitID)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Color.black)
#else
            // macOS native: placeholder
            Color.clear.frame(height: 0)
#endif
        }
    }
}

#if os(iOS)
import UIKit

private struct GADBannerRepresentable: UIViewRepresentable {

    let adUnitID: String

    func makeUIView(context: Context) -> UIView {
        // To enable AdMob: import GoogleMobileAds and replace below with:
        // let banner = GADBannerView(adSize: GADCurrentOrientationAnchoredAdaptiveBannerAdSizeWithWidth(UIScreen.main.bounds.width))
        // banner.adUnitID = adUnitID
        // banner.rootViewController = context.coordinator.rootVC()
        // banner.load(GADRequest())
        // return banner
        return UIView()
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}
#endif

#else
// tvOS — AppLovin interstitials are used instead of banners.
// Provide an empty struct so imports compile.
struct BannerAdView: View {
    var body: some View { EmptyView() }
}
#endif
