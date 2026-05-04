import SwiftUI
import SwiftData

#if os(macOS)
@main
struct StreamArcApp: App {

    @State private var appEnv = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            ContentRootView()
                .environment(appEnv)
                .environment(appEnv.entitlementManager)
                .environment(appEnv.storeManager)
                .environment(appEnv.adsManager)
                .environment(appEnv.interstitialAdManager)
                .environment(appEnv.settingsStore)
                .preferredColorScheme(appEnv.settingsStore.colorScheme)
                .task { await appEnv.onAppear() }
        }
        .modelContainer(for: [Profile.self, FavoriteItem.self, WatchHistoryEntry.self])
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About StreamArc") { }
            }
            CommandGroup(after: .newItem) {
                Button("Home") {
                    NotificationCenter.default.post(name: .switchToTab, object: HomeView.Tab.home)
                }
                .keyboardShortcut("0", modifiers: .command)
                Button("Live TV") {
                    NotificationCenter.default.post(name: .switchToTab, object: HomeView.Tab.liveTV)
                }
                .keyboardShortcut("1", modifiers: .command)
                Button("Movies") {
                    NotificationCenter.default.post(name: .switchToTab, object: HomeView.Tab.movies)
                }
                .keyboardShortcut("2", modifiers: .command)
                Button("Series") {
                    NotificationCenter.default.post(name: .switchToTab, object: HomeView.Tab.series)
                }
                .keyboardShortcut("3", modifiers: .command)
                Button("Search") {
                    NotificationCenter.default.post(name: .switchToTab, object: HomeView.Tab.search)
                }
                .keyboardShortcut("f", modifiers: .command)
                Button("EPG / TV Guide") {
                    NotificationCenter.default.post(name: .switchToTab, object: HomeView.Tab.epg)
                }
                .keyboardShortcut("4", modifiers: .command)
                Button("Settings") {
                    NotificationCenter.default.post(name: .switchToTab, object: HomeView.Tab.settings)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

#endif

