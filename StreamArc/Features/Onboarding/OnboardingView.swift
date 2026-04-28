import StreamArcCore
import SwiftUI

struct OnboardingView: View {
    @State private var showAddProfile = false

    var body: some View {
        ZStack {
            Color.saBackground.ignoresSafeArea()

            VStack(spacing: 40) {
                Spacer()

                // Logo / wordmark
                VStack(spacing: 12) {
                    Image(systemName: "play.tv.fill")
                        .font(.system(size: 72))
                        .foregroundStyle(Color.saAccent)
                    Text("StreamArc")
                        .font(.system(size: 44, weight: .black, design: .rounded))
                        .foregroundStyle(Color.saTextPrimary)
                    Text("Your streams. Your sources.")
                        .font(.title3)
                        .foregroundStyle(Color.saTextSecondary)
                }

                // Feature pills
                VStack(spacing: 10) {
                    ForEach(["M3U Playlists", "Xtream Codes", "MAG / Stalker", "Enigma2"], id: \.self) { label in
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.saAccent)
                            Text(label)
                                .foregroundStyle(Color.saTextPrimary)
                            Spacer()
                        }
                        .padding(.horizontal, 24)
                    }
                }
                .padding(.vertical, 20)
                .background(Color.saSurface)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal, 32)

                Spacer()

                Button("Add Your First Source") {
                    showAddProfile = true
                }
                .buttonStyle(AccentButtonStyle())
                .padding(.bottom, 48)
            }
        }
        .sheet(isPresented: $showAddProfile) {
            AddProfileView()
        }
    }
}
