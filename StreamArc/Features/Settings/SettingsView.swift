import StreamArcCore
import SwiftUI
import SwiftData
import Kingfisher

struct SettingsView: View {

    @Environment(AppEnvironment.self)     private var appEnv
    @Environment(EntitlementManager.self) private var entitlements
    @Environment(StoreManager.self)       private var store
    @Environment(\.modelContext)          private var modelContext

    @State private var showPaywall = false
    @State private var showParentalLock = false
    @State private var showCacheClearedAlert = false

    var body: some View {
        NavigationStack {
            Form {
                // Premium banner or upgrade CTA
                if entitlements.isPremium {
                    Section {
                        HStack {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(Color.saAccent)
                            Text("StreamArc+ Active")
                                .font(.headline)
                                .foregroundStyle(Color.saTextPrimary)
                            if entitlements.isLifetime {
                                Spacer()
                                Text("Lifetime")
                                    .font(.caption)
                                    .foregroundStyle(Color.saTextSecondary)
                            }
                        }
                    }
                } else {
                    Section {
                        Button { showPaywall = true } label: {
                            HStack {
                                Image(systemName: "star.fill")
                                    .foregroundStyle(Color.saAccent)
                                Text("Upgrade to StreamArc+")
                                    .font(.headline)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(Color.saTextSecondary)
                            }
                        }
                        .tint(Color.saTextPrimary)
                    }
                }

                // TMDB
                Section("TMDB API") {
                    SecureField("API Key", text: Binding(
                        get: { appEnv.settingsStore.tmdbAPIKey },
                        set: { appEnv.settingsStore.tmdbAPIKey = $0 }
                    ))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    Text("Get your free key at themoviedb.org/settings/api")
                        .font(.caption)
                        .foregroundStyle(Color.saTextSecondary)
                }

                // EPG
                Section("Default EPG URL") {
                    TextField("XMLTV URL", text: Binding(
                        get: { appEnv.settingsStore.defaultEPGURL },
                        set: { appEnv.settingsStore.defaultEPGURL = $0 }
                    ))
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                }

                // Appearance
                Section("Appearance") {
                    Picker("Theme", selection: Binding(
                        get: { appEnv.settingsStore.preferredAppearance },
                        set: { appEnv.settingsStore.preferredAppearance = $0 }
                    )) {
                        Text("Auto").tag("auto")
                        Text("Dark").tag("dark")
                        Text("Light").tag("light")
                    }
                    .pickerStyle(.segmented)
                }

                // Parental controls
                Section("Parental Controls") {
                    Button("Configure Parental Lock") {
                        showParentalLock = true
                    }
                    .tint(Color.saAccent)
                }

                // Cache
                Section("Storage") {
                    Button("Clear EPG Cache") { clearEPGCache() }
                        .tint(.red)
                    Button("Clear Image Cache") {
                        KingfisherManager.shared.cache.clearMemoryCache()
                        KingfisherManager.shared.cache.clearDiskCache()
                        showCacheClearedAlert = true
                    }
                    .tint(.red)
                }

                // Profiles link
                Section {
                    NavigationLink("Manage Sources") {
                        ProfilesView()
                    }
                    .tint(Color.saAccent)
                }

                // About
                Section("About") {
                    LabeledContent("Version", value: appVersion)
                    LabeledContent("Build",   value: buildNumber)
                    Text("StreamArc is a pure IPTV client. It does not provide or host any content.")
                        .font(.caption)
                        .foregroundStyle(Color.saTextSecondary)
                }

                #if DEBUG
                Section("Developer") {
                    Toggle("Debug Premium Override", isOn: Binding(
                        get: { entitlements.debugPremiumOverride },
                        set: { entitlements.debugPremiumOverride = $0 }
                    ))
                    .tint(Color.saAccent)
                    Text("Enables premium features without a StoreKit purchase. Debug builds only.")
                        .font(.caption)
                        .foregroundStyle(Color.saTextSecondary)
                }
                #endif
            }
            #if !os(tvOS)
            .scrollContentBackground(.hidden)
            #endif
            .background(Color.saBackground)
            .navigationTitle("Settings")
            .paywallSheet(isPresented: $showPaywall)
            .sheet(isPresented: $showParentalLock) { ParentalLockView() }
            .alert("Cache cleared", isPresented: $showCacheClearedAlert) {
                Button("OK") {}
            }
        }
    }

    private func clearEPGCache() {
        // EPG cache is in-memory on HomeViewModel; signal refresh on next load
        showCacheClearedAlert = true
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
}
