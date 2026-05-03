import StreamArcCore
import SwiftUI
import SwiftData

/// Shown on startup when the user has more than one source configured.
/// The user taps a source card to activate it; the closure fires and content loading begins.
struct SourcePickerView: View {

    let profiles: [Profile]
    var onSelect: (Profile) -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var hoveredId: String? = nil

    var body: some View {
        ZStack {
            // Blurred background
            Color.saBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                VStack(spacing: 8) {
                    Image("AppLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 44)
                        .padding(.bottom, 4)

                    Text("Choose a Source")
                        .font(.title2.bold())
                        .foregroundStyle(Color.saTextPrimary)

                    Text("Select which source to load")
                        .font(.subheadline)
                        .foregroundStyle(Color.saTextSecondary)
                }
                .padding(.top, 48)
                .padding(.bottom, 32)

                // Source cards
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(profiles) { profile in
                            sourceCard(profile)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
                }
            }
        }
    }

    private func sourceCard(_ profile: Profile) -> some View {
        Button {
            activate(profile)
        } label: {
            HStack(spacing: 16) {
                // Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.saAccent.opacity(0.15))
                        .frame(width: 52, height: 52)
                    Image(systemName: profile.sourceType.systemImage)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Color.saAccent)
                }

                // Name & type
                VStack(alignment: .leading, spacing: 4) {
                    Text(profile.name)
                        .font(.headline)
                        .foregroundStyle(Color.saTextPrimary)
                        .lineLimit(1)
                    Text(profile.sourceType.rawValue)
                        .font(.caption)
                        .foregroundStyle(Color.saTextSecondary)
                    if let loaded = profile.lastLoadedAt {
                        Text("Last used \(loaded.formatted(.relative(presentation: .named)))")
                            .font(.caption2)
                            .foregroundStyle(Color.saTextSecondary.opacity(0.7))
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(Color.saTextSecondary.opacity(0.5))
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(profile.isActive ? Color.saAccent.opacity(0.1) : Color.saCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(
                                profile.isActive ? Color.saAccent.opacity(0.5) : Color.white.opacity(0.05),
                                lineWidth: profile.isActive ? 1.5 : 1
                            )
                    )
            )
            .overlay(alignment: .topTrailing) {
                if profile.isActive {
                    Label("Last used", systemImage: "checkmark.circle.fill")
                        .labelStyle(.iconOnly)
                        .font(.system(size: 18))
                        .foregroundStyle(Color.saAccent)
                        .padding(10)
                }
            }
        }
        .buttonStyle(.plain)
        .cardFocusable()
        #if os(macOS)
        .onHover { hoveredId = $0 ? profile.id : nil }
        .scaleEffect(hoveredId == profile.id ? 1.01 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: hoveredId)
        #endif
    }

    private func activate(_ profile: Profile) {
        profiles.forEach { $0.isActive = false }
        profile.isActive = true
        try? modelContext.save()
        onSelect(profile)
    }
}
