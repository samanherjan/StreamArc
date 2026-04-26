import SwiftUI
import SwiftData

#if os(iOS)
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
                .environment(appEnv.settingsStore)
                .preferredColorScheme(appEnv.settingsStore.colorScheme)
                .task { await appEnv.onAppear() }
        }
        .modelContainer(for: [Profile.self, FavoriteItem.self, WatchHistoryEntry.self])
    }
}
#endif
