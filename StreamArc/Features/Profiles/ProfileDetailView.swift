import StreamArcCore
import SwiftUI

struct ProfileDetailView: View {
    let profile: Profile
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var epgURL: String

    init(profile: Profile) {
        self.profile = profile
        _name   = State(initialValue: profile.name)
        _epgURL = State(initialValue: profile.epgURL ?? "")
    }

    var body: some View {
        Form {
            Section("Profile") {
                TextField("Name", text: $name)
                Label(profile.sourceType.rawValue, systemImage: profile.sourceType.systemImage)
                    .foregroundStyle(Color.saTextSecondary)
            }

            Section("Connection Details") {
                switch profile.sourceType {
                case .m3u:
                    if let url = profile.m3uURL { LabeledContent("URL", value: url) }
                case .stalker:
                    if let url = profile.portalURL { LabeledContent("Portal", value: url) }
                    if let mac = profile.macAddress { LabeledContent("MAC", value: mac) }
                case .xtream:
                    if let url = profile.xtreamURL { LabeledContent("Server", value: url) }
                    if let user = profile.xtreamUsername { LabeledContent("Username", value: user) }
                case .enigma2:
                    if let url = profile.enigma2URL { LabeledContent("Box URL", value: url) }
                }
            }

            Section("EPG") {
                TextField("XMLTV URL (optional)", text: $epgURL)
                    .urlTextField()
                    .autocorrectionDisabled()
            }

            Section {
                if let date = profile.lastLoadedAt {
                    LabeledContent("Last loaded", value: date.formatted(date: .abbreviated, time: .shortened))
                }
            }
        }
        #if !os(tvOS)
        .scrollContentBackground(.hidden)
        #endif
        .background(Color.saBackground)
        .navigationTitle(profile.name)
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .tint(Color.saAccent)
            }
        }
    }

    private func save() {
        profile.name = name
        profile.epgURL = epgURL.isEmpty ? nil : epgURL
        try? modelContext.save()
        dismiss()
    }
}
