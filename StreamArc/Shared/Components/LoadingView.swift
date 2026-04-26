import SwiftUI

struct LoadingView: View {
    var message: String = "Loading…"

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(.saAccent)
                .scaleEffect(1.4)
            Text(message)
                .font(.callout)
                .foregroundStyle(Color.saTextSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .streamArcBackground()
    }
}

// Shimmer skeleton placeholder for poster grids
struct ShimmerCard: View {

    @State private var phase: CGFloat = 0

    var body: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(shimmerGradient)
            .onAppear {
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }

    private var shimmerGradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: Color.saSurface, location: phase - 0.3),
                .init(color: Color.saCard.opacity(0.8), location: phase),
                .init(color: Color.saSurface, location: phase + 0.3)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

struct ShimmerGrid: View {
    var columns: Int = 3
    var itemCount: Int = 12

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: columns), spacing: 12) {
            ForEach(0..<itemCount, id: \.self) { _ in
                ShimmerCard()
                    .aspectRatio(2/3, contentMode: .fit)
            }
        }
        .padding(.horizontal)
    }
}
