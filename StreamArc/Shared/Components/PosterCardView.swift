import SwiftUI
import Kingfisher

struct PosterCardView: View {
    let title: String
    let imageURL: String?
    var isLocked: Bool = false
    var cornerRadius: CGFloat = 10

    var body: some View {
        ZStack(alignment: .bottom) {
            posterImage

            // Gradient title overlay
            LinearGradient(
                colors: [.clear, .black.opacity(0.85)],
                startPoint: .center,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .padding([.horizontal, .bottom], 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isLocked {
                Color.black.opacity(0.5)
                Image(systemName: "lock.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    @ViewBuilder
    private var posterImage: some View {
        if let urlString = imageURL, let url = URL(string: urlString) {
            KFImage(url)
                .resizable()
                .placeholder { ShimmerCard() }
                .fade(duration: 0.25)
                .scaledToFill()
        } else {
            Rectangle()
                .fill(Color.saSurface)
                .overlay {
                    Image(systemName: "photo")
                        .font(.largeTitle)
                        .foregroundStyle(Color.saTextSecondary)
                }
        }
    }
}

#Preview {
    PosterCardView(title: "The Dark Knight", imageURL: nil)
        .frame(width: 120, height: 180)
        .padding()
        .background(Color.saBackground)
}
