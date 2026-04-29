import StreamArcCore
import SwiftUI
import SwiftData

struct AddProfileView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss)      private var dismiss
    @Environment(EntitlementManager.self) private var entitlements
    @Query private var profiles: [Profile]

    @State private var selectedType: SourceType = .m3u
    @State private var name = ""

    // M3U
    @State private var m3uURL = ""
    @State private var showFileImporter = false

    // Stalker
    @State private var portalURL = ""
    @State private var macAddress = ""

    // Xtream
    @State private var xtreamURL = ""
    @State private var xtreamUsername = ""
    @State private var xtreamPassword = ""

    // Enigma2
    @State private var enigma2URL = ""

    // Shared
    @State private var epgURL = ""

    @State private var isTesting = false
    @State private var testResult: TestResult?
    @State private var showPaywall = false

    enum TestResult { case success, failure(String) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Source Type") {
                    Picker("Type", selection: $selectedType) {
                        ForEach(SourceType.allCases, id: \.self) { type in
                            HStack {
                                Image(systemName: type.systemImage)
                                Text(type.rawValue)
                                if type.isPremiumRequired {
                                    Spacer()
                                    PremiumBadgeView()
                                }
                            }
                            .tag(type)
                        }
                    }
                    .pickerStyle(.inline)
                    .onChange(of: selectedType) { _, new in
                        if new.isPremiumRequired && !entitlements.isPremium {
                            selectedType = .m3u
                            showPaywall = true
                        }
                    }
                }

                Section("Profile Name") {
                    TextField("My Provider", text: $name)
                }

                formFields

                Section("EPG (Optional)") {
                    TextField("XMLTV URL", text: $epgURL)
                        .urlTextField()
                        .autocorrectionDisabled()
                }

                Section {
                    Button {
                        Task { await testConnection() }
                    } label: {
                        HStack {
                            if isTesting {
                                ProgressView().tint(.saAccent)
                            } else {
                                Image(systemName: "network")
                            }
                            Text("Test Connection")
                        }
                    }
                    .tint(Color.saAccent)
                    .disabled(isTesting || !canTest)

                    if let result = testResult {
                        switch result {
                        case .success:
                            Label("Connection successful", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        case .failure(let msg):
                            Label(msg, systemImage: "xmark.circle.fill")
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
            #if !os(tvOS)
            .scrollContentBackground(.hidden)
            #endif
            .background(Color.saBackground)
            .navigationTitle("Add Source")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                        .tint(Color.saAccent)
                }
            }
            .paywallSheet(isPresented: $showPaywall)
#if os(iOS)
            .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.init(filenameExtension: "m3u")!, .init(filenameExtension: "m3u8")!]) { result in
                if case .success(let url) = result {
                    m3uURL = url.absoluteString
                }
            }
#endif
        }
    }

    // MARK: - Form fields per source type

    @ViewBuilder
    private var formFields: some View {
        switch selectedType {
        case .m3u:
            Section("M3U Source") {
                TextField("Playlist URL (http://...)", text: $m3uURL)
                    .urlTextField()
                    .autocorrectionDisabled()

                if let creds = M3UParser.extractXtreamCredentials(from: m3uURL) {
                    Button {
                        xtreamURL = creds.baseURL
                        xtreamUsername = creds.username
                        xtreamPassword = creds.password
                        selectedType = .xtream
                    } label: {
                        Label("Xtream Codes detected — tap to use Xtream mode (recommended)", systemImage: "arrow.right.circle.fill")
                            .font(.caption)
                            .foregroundStyle(Color.saAccent)
                    }
                }

#if os(iOS) || os(macOS)
                Button("Import Local File…") { showFileImporter = true }
                    .tint(Color.saAccent)
#endif
            }
        case .stalker:
            Section("MAG / Stalker Portal") {
                TextField("Portal URL", text: $portalURL)
                    .urlTextField()
                    .autocorrectionDisabled()
                TextField("MAC Address (00:1A:79:XX:XX:XX)", text: $macAddress)
                    .noAutocapitalization()
                    .autocorrectionDisabled()
            }
        case .xtream:
            Section("Xtream Codes") {
                TextField("Server URL", text: $xtreamURL)
                    .urlTextField()
                    .autocorrectionDisabled()
                TextField("Username", text: $xtreamUsername)
                    .noAutocapitalization()
                    .autocorrectionDisabled()
                SecureField("Password", text: $xtreamPassword)
            }
        case .enigma2:
            Section("Enigma2 Box") {
                TextField("Box IP / URL (http://192.168.1.x)", text: $enigma2URL)
                    .urlTextField()
                    .autocorrectionDisabled()
            }
        }
    }

    // MARK: - Validation

    private var canTest: Bool {
        switch selectedType {
        case .m3u:     return !m3uURL.isEmpty
        case .stalker: return !portalURL.isEmpty && !macAddress.isEmpty
        case .xtream:  return !xtreamURL.isEmpty && !xtreamUsername.isEmpty
        case .enigma2: return !enigma2URL.isEmpty
        }
    }

    private var canSave: Bool { !name.isEmpty && canTest }

    // MARK: - Actions

    private func testConnection() async {
        isTesting = true
        testResult = nil
        defer { isTesting = false }
        do {
            switch selectedType {
            case .m3u:
                guard let url = URL(string: m3uURL) else { throw URLError(.badURL) }
                let result = try await M3UParser.parse(url: url)
                if result.channels.isEmpty && result.vodItems.isEmpty {
                    testResult = .failure("No channels found — check URL and credentials")
                } else {
                    testResult = .success
                }
            case .stalker:
                let client = StalkerClient(config: .init(portalURL: portalURL, macAddress: macAddress))
                try await client.authenticate()
                testResult = .success
            case .xtream:
                let client = XtreamClient(config: .init(baseURL: xtreamURL, username: xtreamUsername, password: xtreamPassword))
                let cats = try await client.liveCategories()
                testResult = cats.isEmpty ? .failure("Authenticated but no categories found") : .success
            case .enigma2:
                let client = Enigma2Client(config: .init(baseURL: enigma2URL))
                let bouquets = try await client.bouquets()
                testResult = bouquets.isEmpty ? .failure("Connected but no bouquets found") : .success
            }
        } catch {
            testResult = .failure(error.localizedDescription)
        }
    }

    private func save() {
        let hasActive = profiles.contains { $0.isActive }

        // If user pasted an Xtream M3U URL, save as Xtream for reliability
        let effectiveType: SourceType
        if selectedType == .m3u,
           let creds = M3UParser.extractXtreamCredentials(from: m3uURL) {
            effectiveType = .xtream
            xtreamURL = creds.baseURL
            xtreamUsername = creds.username
            xtreamPassword = creds.password
        } else {
            effectiveType = selectedType
        }

        let profile = Profile(name: name, sourceType: effectiveType, isActive: !hasActive)
        switch effectiveType {
        case .m3u:
            profile.m3uURL = m3uURL
        case .stalker:
            profile.portalURL = portalURL
            profile.macAddress = macAddress
        case .xtream:
            profile.xtreamURL = xtreamURL
            profile.xtreamUsername = xtreamUsername
            profile.xtreamPassword = xtreamPassword
        case .enigma2:
            profile.enigma2URL = enigma2URL
        }
        profile.epgURL = epgURL.isEmpty ? nil : epgURL
        modelContext.insert(profile)
        try? modelContext.save()
        dismiss()
    }
}
