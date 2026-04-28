import SwiftUI
import YouTubePlayerKit

struct TrailerPlayerView: View {
    let videoId: String
    @Environment(\.dismiss) private var dismiss

    @State private var player: YouTubePlayer

    init(videoId: String) {
        self.videoId = videoId
        self._player = State(wrappedValue: YouTubePlayer(
            source: .video(id: videoId),
            configuration: .init(
                autoPlay: true,
                showControls: true,
                showFullscreenButton: false,
                playInline: true,
                showRelatedVideos: false
            )
        ))
    }

    var body: some View {
        NavigationStack {
            YouTubePlayerView(player)
                .ignoresSafeArea()
                .background(Color.black)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                            .foregroundStyle(.white)
                    }
                }
        }
    }
}
