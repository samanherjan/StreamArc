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
                Button("Live TV") { }
                    .keyboardShortcut("1", modifiers: .command)
                Button("Movies") { }
                    .keyboardShortcut("2", modifiers: .command)
                Button("Series") { }
                    .keyboardShortcut("3", modifiers: .command)
            }
        }
    }
}
#endif
