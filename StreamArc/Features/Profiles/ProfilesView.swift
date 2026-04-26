import SwiftUI
import SwiftData

struct ProfilesView: View {
    @Query(sort: \Profile.createdAt) private var profiles: [Profile]
    @Environment(\.modelContext) private var modelContext
    @Environment(EntitlementManager.self) private var entitlements
    @State private var showAddProfile = false
    @State private var showPaywall = false
    @State private var profileToDelete: Profile?

    var body: some View {
        NavigationStack {
            List {
                ForEach(profiles) { profile in
                    NavigationLink(destination: ProfileDetailView(profile: profile)) {
                        ProfileRow(profile: profile, isActive: profile.isActive) {
                            activateProfile(profile)
                        }
                    }
                    .listRowBackground(Color.saSurface)
                }
                .onDelete { indexSet in
                    for i in indexSet { profileToDelete = profiles[i] }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.saBackground)
            .navigationTitle("Sources")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { addProfileTapped() } label: {
                        Image(systemName: "plus")
                    }
                    .tint(Color.saAccent)
                }
            }
        }
        .sheet(isPresented: $showAddProfile) { AddProfileView() }
        .paywallSheet(isPresented: $showPaywall)
        .alert("Delete Source?", isPresented: .constant(profileToDelete != nil)) {
            Button("Delete", role: .destructive) {
                if let p = profileToDelete { delete(p) }
                profileToDelete = nil
            }
            Button("Cancel", role: .cancel) { profileToDelete = nil }
        } message: {
            Text("This will remove "\(profileToDelete?.name ?? "")" and its data.")
        }
    }

    private func addProfileTapped() {
        if !entitlements.isPremium && profiles.count >= 1 {
            showPaywall = true
        } else {
            showAddProfile = true
        }
    }

    private func activateProfile(_ profile: Profile) {
        profiles.forEach { $0.isActive = false }
        profile.isActive = true
        try? modelContext.save()
    }

    private func delete(_ profile: Profile) {
        modelContext.delete(profile)
        try? modelContext.save()
    }
}

private struct ProfileRow: View {
    let profile: Profile
    let isActive: Bool
    let onActivate: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: profile.sourceType.systemImage)
                .frame(width: 36, height: 36)
                .background(Color.saAccent.opacity(0.2))
                .foregroundStyle(Color.saAccent)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(profile.name)
                    .font(.headline)
                    .foregroundStyle(Color.saTextPrimary)
                Text(profile.sourceType.rawValue)
                    .font(.caption)
                    .foregroundStyle(Color.saTextSecondary)
            }
            Spacer()
            if isActive {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.saAccent)
            } else {
                Button("Use") { onActivate() }
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
        .padding(.vertical, 4)
    }
}
