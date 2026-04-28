import SwiftUI
import SwiftData

// Root environment object — injected at the WindowGroup level.
// Holds cross-cutting state that all views need access to.
@MainActor
@Observable
final class AppEnvironment {

    var entitlementManager: EntitlementManager
    var storeManager: StoreManager
    var adsManager: AdsManager
    var interstitialAdManager: InterstitialAdManager
    var settingsStore: SettingsStore

    init() {
        let settings = SettingsStore()
        let entitlement = EntitlementManager()
        self.settingsStore = settings
        self.entitlementManager = entitlement
        self.storeManager = StoreManager(entitlementManager: entitlement)
        self.adsManager = AdsManager(entitlementManager: entitlement)
        self.interstitialAdManager = InterstitialAdManager(entitlementManager: entitlement)
    }

    func onAppear() async {
        await storeManager.loadProducts()
        await entitlementManager.refresh()
        await adsManager.initialize()
        interstitialAdManager.preload()
    }
}

// Simple UserDefaults-backed settings store.
@MainActor
@Observable
final class SettingsStore {

    var tmdbAPIKey: String {
        get { UserDefaults.standard.string(forKey: "tmdb_api_key") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "tmdb_api_key") }
    }

    var defaultEPGURL: String {
        get { UserDefaults.standard.string(forKey: "default_epg_url") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "default_epg_url") }
    }

    var parentalLockEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "parental_lock_enabled") }
        set { UserDefaults.standard.set(newValue, forKey: "parental_lock_enabled") }
    }

    var parentalPIN: String {
        get { UserDefaults.standard.string(forKey: "parental_pin") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "parental_pin") }
    }

    var preferredAppearance: String {
        get { UserDefaults.standard.string(forKey: "appearance") ?? "auto" }
        set { UserDefaults.standard.set(newValue, forKey: "appearance") }
    }

    var colorScheme: ColorScheme? {
        switch preferredAppearance {
        case "light": return .light
        case "dark":  return .dark
        default:      return nil
        }
    }
}
