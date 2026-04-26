import SwiftUI
import Kingfisher

struct MovieDetailView: View {
    let item: VODItem
    @Environment(\.dismiss) private var dismiss
    @Environment(EntitlementManager.self) private var entitlements
    @State private var showPlayer = false
    @State private var showPaywall = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Hero poster
                    if let posterURL = item.posterURL, let url = URL(string: posterURL) {
                        KFImage(url)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 360)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .padding(.horizontal)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        // Title + year
                        HStack(alignment: .firstTextBaseline) {
                            Text(item.title)
                                .font(.title2.bold())
                                .foregroundStyle(Color.saTextPrimary)
                            if let year = item.year {
                                Text(String(year))
                                    .font(.title3)
                                    .foregroundStyle(Color.saTextSecondary)
                            }
                        }

                        // Description
                        if let desc = item.description {
                            Text(desc)
                                .font(.body)
                                .foregroundStyle(Color.saTextSecondary)
                        }

                        // Group / category
                        if !item.groupTitle.isEmpty {
                            Label(item.groupTitle, systemImage: "folder")
                                .font(.caption)
                                .foregroundStyle(Color.saTextSecondary)
                        }

                        // Action buttons
                        HStack(spacing: 12) {
                            // Play button
                            Button {
                                showPlayer = true
                            } label: {
                                Label("Play", systemImage: "play.fill")
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 24)
                                    .padding(.vertical, 12)
                                    .background(Color.saAccent)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)

                            // Trailer button (premium)
                            TrailerButton(item: item)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 32)
                }
            }
            .background(Color.saBackground)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .fullScreenCover(isPresented: $showPlayer) {
            PlayerView(streamURL: item.streamURL, title: item.title)
        }
    }
}
